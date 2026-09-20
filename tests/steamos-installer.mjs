import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { createServer } from 'node:http'
import { chmod, mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { spawn } from 'node:child_process'

const installerPath = resolve('installers/steamos/install.sh')
const testRoot = await mkdtemp(join(tmpdir(), 'tegra-steamos-test-'))
const fakeBin = join(testRoot, 'bin')
const homeDir = join(testRoot, 'home')
const dataHome = join(testRoot, 'data')
const steamCallPath = join(testRoot, 'steam-call.txt')
const appImageBody = Buffer.from('mock Tegra AppImage\n', 'utf8')
const betaAppImageBody = Buffer.from('mock Tegra beta AppImage\n', 'utf8')
const nightlyAppImageBody = Buffer.from('mock Tegra nightly AppImage\n', 'utf8')
const experimentalAppImageBody = Buffer.from('mock Tegra experimental AppImage\n', 'utf8')
const iconBody = Buffer.from('mock icon\n', 'utf8')
const checksum = createHash('sha512').update(appImageBody).digest('base64')
const betaChecksum = createHash('sha512').update(betaAppImageBody).digest('base64')
const nightlyChecksum = createHash('sha512').update(nightlyAppImageBody).digest('base64')
const experimentalChecksum = createHash('sha512').update(experimentalAppImageBody).digest('base64')

await mkdir(fakeBin, { recursive: true })
await mkdir(homeDir, { recursive: true })

async function writeExecutable(name, content) {
  const path = join(fakeBin, name)
  await writeFile(path, content, 'utf8')
  await chmod(path, 0o755)
}

await writeExecutable('id', '#!/usr/bin/env bash\nif [[ "${1:-}" == "-u" ]]; then printf "1000\\n"; else /usr/bin/id "$@"; fi\n')
await writeExecutable('uname', '#!/usr/bin/env bash\nprintf "x86_64\\n"\n')
await writeExecutable(
  'steamos-add-to-steam',
  '#!/usr/bin/env bash\nprintf "%s\\n" "$1" > "$TEGRA_TEST_STEAM_CALL_PATH"\n',
)

let currentChecksum = checksum
const currentBetaChecksum = betaChecksum
const currentNightlyChecksum = nightlyChecksum
const currentExperimentalChecksum = experimentalChecksum
const server = createServer((request, response) => {
  const address = server.address()
  assert.notEqual(address, null)
  assert.equal(typeof address, 'object')
  const origin = `http://127.0.0.1:${address.port}`

  if (request.url === '/api/downloads/versions') {
    response.setHeader('content-type', 'application/json')
    response.end(JSON.stringify({
      linux: {
        version: '1.2.3',
        name: '',
        url: `${origin}/Tegra.AppImage`,
        checksum: currentChecksum,
      },
      beta: {
        linux: {
          version: '1.3.0-beta.1',
          name: '',
          url: `${origin}/Tegra-beta.AppImage`,
          checksum: currentBetaChecksum,
        },
      },
      nightly: {
        linux: {
          version: '1.4.0-nightly.1',
          name: 'Tegra-Linux-1.4.0-nightly.1.AppImage',
          url: `${origin}/Tegra-nightly.AppImage`,
          checksum: currentNightlyChecksum,
        },
      },
      experimental: {
        linux: {
          version: '1.5.0-experimental.1',
          name: 'Tegra-Linux-1.5.0-experimental.1.AppImage',
          url: `${origin}/Tegra-experimental.AppImage`,
          checksum: currentExperimentalChecksum,
        },
      },
    }))
    return
  }

  if (request.url === '/Tegra.AppImage') {
    response.end(appImageBody)
    return
  }

  if (request.url === '/Tegra-beta.AppImage') {
    response.end(betaAppImageBody)
    return
  }

  if (request.url === '/Tegra-nightly.AppImage') {
    response.end(nightlyAppImageBody)
    return
  }

  if (request.url === '/Tegra-experimental.AppImage') {
    response.end(experimentalAppImageBody)
    return
  }

  if (request.url === '/tegra-logo.png') {
    response.end(iconBody)
    return
  }

  response.statusCode = 404
  response.end('not found')
})

await new Promise((resolvePromise) => server.listen(0, '127.0.0.1', resolvePromise))
const serverAddress = server.address()
assert.notEqual(serverAddress, null)
assert.equal(typeof serverAddress, 'object')
const origin = `http://127.0.0.1:${serverAddress.port}`

function runInstaller(args = [], extraEnv = {}) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn('bash', [installerPath, ...args], {
      cwd: dirname(installerPath),
      env: {
        ...process.env,
        HOME: homeDir,
        XDG_DATA_HOME: dataHome,
        PATH: `${fakeBin}:${process.env.PATH}`,
        LANG: 'en_US.UTF-8',
        TEGRA_ALLOW_INSECURE_TEST_URLS: '1',
        TEGRA_DOWNLOADS_API_URL: `${origin}/api/downloads/versions`,
        TEGRA_ICON_URL: `${origin}/tegra-logo.png`,
        TEGRA_TEST_STEAM_CALL_PATH: steamCallPath,
        ...extraEnv,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    })

    let stdout = ''
    let stderr = ''
    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', rejectPromise)
    child.on('close', (code) => resolvePromise({ code, stdout, stderr }))
  })
}

try {
  const firstRun = await runInstaller()
  assert.equal(firstRun.code, 0, `${firstRun.stdout}\n${firstRun.stderr}`)

  const installedAppImage = join(dataHome, 'tegra', 'Tegra.AppImage')
  const desktopPath = join(dataHome, 'applications', 'com.seijin.tegramc.app.desktop')
  assert.deepEqual(await readFile(installedAppImage), appImageBody)
  assert.match(firstRun.stdout, /Tegra.AppImage/)
  assert.ok((await stat(installedAppImage)).mode & 0o100)
  assert.ok((await readFile(desktopPath, 'utf8')).includes(`Exec="${installedAppImage}" %U`))
  assert.equal((await readFile(steamCallPath, 'utf8')).trim(), desktopPath)

  await writeFile(steamCallPath, '', 'utf8')
  const secondRun = await runInstaller()
  assert.equal(secondRun.code, 0, `${secondRun.stdout}\n${secondRun.stderr}`)
  assert.equal(await readFile(steamCallPath, 'utf8'), '')
  assert.match(secondRun.stdout, /Steam shortcut was already requested/)

  const betaRun = await runInstaller(['--beta'])
  assert.equal(betaRun.code, 0, `${betaRun.stdout}\n${betaRun.stderr}`)
  assert.match(betaRun.stdout, /latest beta release/)
  assert.match(betaRun.stdout, /Tegra-beta.AppImage/)
  assert.deepEqual(await readFile(installedAppImage), betaAppImageBody)
  assert.equal((await readFile(join(dataHome, 'tegra', 'version'), 'utf8')).trim(), '1.3.0-beta.1')

  const channelRun = await runInstaller(['--channel', 'beta'])
  assert.equal(channelRun.code, 0, `${channelRun.stdout}\n${channelRun.stderr}`)
  assert.deepEqual(await readFile(installedAppImage), betaAppImageBody)

  const inlineChannelRun = await runInstaller(['--channel=beta'])
  assert.equal(inlineChannelRun.code, 0, `${inlineChannelRun.stdout}\n${inlineChannelRun.stderr}`)
  assert.deepEqual(await readFile(installedAppImage), betaAppImageBody)

  const nightlyRun = await runInstaller(['--nightly'])
  assert.equal(nightlyRun.code, 0, `${nightlyRun.stdout}\n${nightlyRun.stderr}`)
  assert.match(nightlyRun.stdout, /latest nightly release/)
  assert.deepEqual(await readFile(installedAppImage), nightlyAppImageBody)

  const experimentalRun = await runInstaller(['--channel', 'experimental'])
  assert.equal(experimentalRun.code, 0, `${experimentalRun.stdout}\n${experimentalRun.stderr}`)
  assert.match(experimentalRun.stdout, /latest experimental release/)
  assert.deepEqual(await readFile(installedAppImage), experimentalAppImageBody)

  const invalidChannelRun = await runInstaller(['--channel', 'preview'])
  assert.equal(invalidChannelRun.code, 2)
  assert.match(invalidChannelRun.stderr, /Invalid channel/)

  const invalidDataHome = join(testRoot, 'invalid-data')
  currentChecksum = Buffer.alloc(64).toString('base64')
  const invalidRun = await runInstaller([], { XDG_DATA_HOME: invalidDataHome })
  assert.notEqual(invalidRun.code, 0)
  assert.match(invalidRun.stderr, /checksum does not match/)

  console.log('SteamOS installer tests passed.')
} finally {
  await new Promise((resolvePromise) => server.close(resolvePromise))
  await rm(testRoot, { recursive: true, force: true })
}
