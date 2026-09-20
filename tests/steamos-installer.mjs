import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { createServer } from 'node:http'
import { access, chmod, mkdir, mkdtemp, readFile, rm, stat, unlink, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { spawn } from 'node:child_process'

const installerPath = resolve('installers/steamos/install.sh')
const testRoot = await mkdtemp(join(tmpdir(), 'tegra-steamos-test-'))
const fakeBin = join(testRoot, 'bin')
const homeDir = join(testRoot, 'home')
const dataHome = join(testRoot, 'data')
const steamCallPath = join(testRoot, 'steam-call.txt')
const steamRoot = join(homeDir, '.local', 'share', 'Steam')
const firstShortcutPath = join(steamRoot, 'userdata', '111', 'config', 'shortcuts.vdf')
const secondShortcutPath = join(steamRoot, 'userdata', '222', 'config', 'shortcuts.vdf')
const unrelatedShortcutPath = join(steamRoot, 'userdata', '333', 'config', 'shortcuts.vdf')
const malformedShortcutPath = join(steamRoot, 'userdata', '444', 'config', 'shortcuts.vdf')
const shortcutFixturePath = join(testRoot, 'tegra-shortcuts.vdf')
const appImageBody = Buffer.from('mock Tegra AppImage\n', 'utf8')
const betaAppImageBody = Buffer.from('mock Tegra beta AppImage\n', 'utf8')
const nightlyAppImageBody = Buffer.from('mock Tegra nightly AppImage\n', 'utf8')
const experimentalAppImageBody = Buffer.from('mock Tegra experimental AppImage\n', 'utf8')
const iconBody = Buffer.from('mock icon\n', 'utf8')
const steamAppId = 0xf1234567

function mockPng(width, height, label) {
  const header = Buffer.alloc(24)
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(header)
  header.writeUInt32BE(13, 8)
  header.write('IHDR', 12, 'ascii')
  header.writeUInt32BE(width, 16)
  header.writeUInt32BE(height, 20)
  return Buffer.concat([header, Buffer.from(label, 'utf8')])
}

const artworkBodies = new Map([
  ['tegra-grid-portrait.png', mockPng(600, 900, 'mock portrait artwork')],
  ['tegra-grid-landscape.png', mockPng(920, 430, 'mock landscape artwork')],
  ['tegra-hero.png', mockPng(1920, 620, 'mock hero artwork')],
  ['tegra-logo.png', mockPng(1280, 720, 'mock logo artwork')],
  ['tegra-icon.png', mockPng(512, 512, 'mock shortcut icon artwork')],
])
const checksum = createHash('sha512').update(appImageBody).digest('base64')
const betaChecksum = createHash('sha512').update(betaAppImageBody).digest('base64')
const nightlyChecksum = createHash('sha512').update(nightlyAppImageBody).digest('base64')
const experimentalChecksum = createHash('sha512').update(experimentalAppImageBody).digest('base64')

await mkdir(fakeBin, { recursive: true })
await mkdir(homeDir, { recursive: true })

function vdfCString(value) {
  return Buffer.concat([Buffer.from(value, 'utf8'), Buffer.from([0])])
}

function vdfString(name, value) {
  return Buffer.concat([Buffer.from([1]), vdfCString(name), vdfCString(value)])
}

function vdfInt32(name, value) {
  const encoded = Buffer.alloc(4)
  encoded.writeInt32LE(value)
  return Buffer.concat([Buffer.from([2]), vdfCString(name), encoded])
}

function vdfObject(name, values) {
  return Buffer.concat([Buffer.from([0]), vdfCString(name), ...values, Buffer.from([8])])
}

function createShortcutsVdf(shortcuts) {
  const entries = shortcuts.map((shortcut, index) => vdfObject(String(index), [
    vdfInt32('appid', shortcut.appid),
    vdfString('AppName', shortcut.appName),
    vdfString('Exe', shortcut.exe),
    vdfString('StartDir', ''),
  ]))
  return Buffer.concat([vdfObject('shortcuts', entries), Buffer.from([8])])
}

async function writeExecutable(name, content) {
  const path = join(fakeBin, name)
  await writeFile(path, content, 'utf8')
  await chmod(path, 0o755)
}

await writeExecutable('id', '#!/usr/bin/env bash\nif [[ "${1:-}" == "-u" ]]; then printf "1000\\n"; else /usr/bin/id "$@"; fi\n')
await writeExecutable('uname', '#!/usr/bin/env bash\nprintf "x86_64\\n"\n')
await writeExecutable(
  'steamos-add-to-steam',
  `#!/usr/bin/env bash
printf '%s\\n' "$1" > "$TEGRA_TEST_STEAM_CALL_PATH"
mkdir -p "$(dirname "$TEGRA_TEST_SHORTCUTS_PATH")" "$(dirname "$TEGRA_TEST_SECOND_SHORTCUTS_PATH")"
cp "$TEGRA_TEST_SHORTCUT_FIXTURE" "$TEGRA_TEST_SHORTCUTS_PATH"
cp "$TEGRA_TEST_SHORTCUT_FIXTURE" "$TEGRA_TEST_SECOND_SHORTCUTS_PATH"
`,
)

const installedAppImage = join(dataHome, 'tegra', 'Tegra.AppImage')
await writeFile(shortcutFixturePath, createShortcutsVdf([{
  appid: steamAppId - 0x100000000,
  appName: 'Tegra',
  exe: `"${installedAppImage}" %U`,
}]))
await mkdir(dirname(unrelatedShortcutPath), { recursive: true })
await writeFile(unrelatedShortcutPath, createShortcutsVdf([{
  appid: 12345,
  appName: 'Another launcher',
  exe: '"/tmp/another-launcher"',
}]))
await mkdir(dirname(malformedShortcutPath), { recursive: true })
await writeFile(malformedShortcutPath, Buffer.from('not a binary VDF', 'utf8'))

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

  const artworkName = request.url?.replace('/assets/', '')
  if (artworkName && artworkBodies.has(artworkName)) {
    response.end(artworkBodies.get(artworkName))
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
        TEGRA_STEAM_ARTWORK_BASE_URL: `${origin}/assets`,
        TEGRA_STEAM_ARTWORK_POLL_ATTEMPTS: '3',
        TEGRA_STEAM_ARTWORK_POLL_INTERVAL: '0.01',
        TEGRA_TEST_STEAM_CALL_PATH: steamCallPath,
        TEGRA_TEST_SHORTCUT_FIXTURE: shortcutFixturePath,
        TEGRA_TEST_SHORTCUTS_PATH: firstShortcutPath,
        TEGRA_TEST_SECOND_SHORTCUTS_PATH: secondShortcutPath,
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

  const desktopPath = join(dataHome, 'applications', 'com.seijin.tegramc.app.desktop')
  assert.deepEqual(await readFile(installedAppImage), appImageBody)
  assert.match(firstRun.stdout, /Tegra.AppImage/)
  assert.ok((await stat(installedAppImage)).mode & 0o100)
  assert.ok((await readFile(desktopPath, 'utf8')).includes(`Exec="${installedAppImage}" %U`))
  assert.equal((await readFile(steamCallPath, 'utf8')).trim(), desktopPath)
  assert.match(firstRun.stdout, /library covers and artwork were installed/)

  const artworkNames = new Map([
    [`${steamAppId}p.png`, artworkBodies.get('tegra-grid-portrait.png')],
    [`${steamAppId}.png`, artworkBodies.get('tegra-grid-landscape.png')],
    [`${steamAppId}_hero.png`, artworkBodies.get('tegra-hero.png')],
    [`${steamAppId}_logo.png`, artworkBodies.get('tegra-logo.png')],
    [`${steamAppId}_icon.png`, artworkBodies.get('tegra-icon.png')],
  ])
  for (const accountId of ['111', '222']) {
    const gridDirectory = join(steamRoot, 'userdata', accountId, 'config', 'grid')
    for (const [name, body] of artworkNames) {
      assert.deepEqual(await readFile(join(gridDirectory, name)), body)
    }
  }
  await assert.rejects(access(join(steamRoot, 'userdata', '333', 'config', 'grid')))
  await assert.rejects(access(join(steamRoot, 'userdata', '444', 'config', 'grid')))

  await writeFile(steamCallPath, '', 'utf8')
  const secondRun = await runInstaller()
  assert.equal(secondRun.code, 0, `${secondRun.stdout}\n${secondRun.stderr}`)
  assert.equal(await readFile(steamCallPath, 'utf8'), '')
  assert.match(secondRun.stdout, /Steam shortcut was already requested/)
  assert.match(secondRun.stdout, /library covers and artwork were installed/)

  await unlink(join(dataHome, 'tegra', '.steam-shortcut-added'))
  const discoveredShortcutRun = await runInstaller()
  assert.equal(discoveredShortcutRun.code, 0, `${discoveredShortcutRun.stdout}\n${discoveredShortcutRun.stderr}`)
  assert.equal(await readFile(steamCallPath, 'utf8'), '')
  assert.match(discoveredShortcutRun.stdout, /shortcut already exists in Steam/)

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

  const missingArtworkRun = await runInstaller([], {
    TEGRA_STEAM_ARTWORK_BASE_URL: `${origin}/missing-assets`,
  })
  assert.equal(missingArtworkRun.code, 0, `${missingArtworkRun.stdout}\n${missingArtworkRun.stderr}`)
  assert.match(missingArtworkRun.stdout, /library artwork could not be completed/)

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
