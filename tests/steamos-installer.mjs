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
const iconBody = Buffer.from('mock icon\n', 'utf8')
const checksum = createHash('sha512').update(appImageBody).digest('base64')

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
        name: 'Tegra-Linux-1.2.3.AppImage',
        url: `${origin}/Tegra.AppImage`,
        checksum: currentChecksum,
      },
    }))
    return
  }

  if (request.url === '/Tegra.AppImage') {
    response.end(appImageBody)
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

function runInstaller(extraEnv = {}) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn('bash', [installerPath], {
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
  assert.ok((await stat(installedAppImage)).mode & 0o100)
  assert.ok((await readFile(desktopPath, 'utf8')).includes(`Exec="${installedAppImage}" %U`))
  assert.equal((await readFile(steamCallPath, 'utf8')).trim(), desktopPath)

  await writeFile(steamCallPath, '', 'utf8')
  const secondRun = await runInstaller()
  assert.equal(secondRun.code, 0, `${secondRun.stdout}\n${secondRun.stderr}`)
  assert.equal(await readFile(steamCallPath, 'utf8'), '')
  assert.match(secondRun.stdout, /Steam shortcut was already requested/)

  const invalidDataHome = join(testRoot, 'invalid-data')
  currentChecksum = Buffer.alloc(64).toString('base64')
  const invalidRun = await runInstaller({ XDG_DATA_HOME: invalidDataHome })
  assert.notEqual(invalidRun.code, 0)
  assert.match(invalidRun.stderr, /checksum does not match/)

  console.log('SteamOS installer tests passed.')
} finally {
  await new Promise((resolvePromise) => server.close(resolvePromise))
  await rm(testRoot, { recursive: true, force: true })
}
