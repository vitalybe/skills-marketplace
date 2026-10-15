import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, UiPressArgument } from 'claude-code'

import type { Band } from '../types'

const band = atom({ plugin: 'workbench', key: 'statusBand' } as const, null)

const GIT_REFRESH_MS = 15_000

const fmt = (n: number) => (n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}k` : `${n}`)

const prettyModel = (id: string) =>
  id
    .replace(/^claude-/, '')
    .replace(/-(\d+)-(\d+)(?=$|-)/, ' $1.$2')
    .replace(/^./, c => c.toUpperCase())

const barColor = (pct: number) => (pct < 60 ? '#5fd787' : pct < 85 ? '#ffaf00' : '#ff5f5f')

const bar = (pct: number, w = 10) => {
  const n = pct > 0 ? Math.max(1, Math.round((pct / 100) * w)) : 0
  return { on: '▰'.repeat(n), off: '▱'.repeat(w - n) }
}

// One refresh at a time; a call that lands mid-refresh folds into one more.
let isBusy = false
let isStale = false
let isTicking = false

async function refresh($: EngineInterface) {
  if (isBusy) {
    isStale = true
    return
  }
  isBusy = true
  try {
    do {
      isStale = false
      const [cwd, model, sessionId, usage] = await Promise.all([
        $.session.cwd(),
        $.session.model(),
        $.session.id(),
        $.session.usage(),
      ])
      const rev = await $.process.run(['git', 'rev-parse', '--show-toplevel', '--git-dir', '--git-common-dir'], { cwd })
      let repo = ''
      let isWorktree = false
      let path = cwd
      let branch = ''
      let changed = 0
      let ahead = 0
      let behind = 0
      if (rev.exitCode === 0) {
        const [top = cwd, gitDir = '', common = ''] = rev.stdout.trim().split('\n')
        const abs = (p: string) => (p.startsWith('/') ? p : `${cwd}/${p}`)
        path = top
        isWorktree = abs(gitDir).replace(/\/$/, '') !== abs(common).replace(/\/$/, '')
        repo = abs(common).replace(/\/\.git\/?$/, '').split('/').pop() ?? ''
        const st = await $.process.run(['git', '--no-optional-locks', 'status', '--porcelain=v2', '-b'], { cwd })
        for (const line of st.stdout.split('\n')) {
          if (line.startsWith('# branch.head ')) branch = line.slice(14)
          else if (line.startsWith('# branch.ab ')) {
            const m = line.match(/\+(\d+) -(\d+)/)
            ahead = Number(m?.[1] ?? 0)
            behind = Number(m?.[2] ?? 0)
          } else if (line && !line.startsWith('#')) changed += 1
        }
      } else {
        repo = cwd.split('/').pop() ?? ''
      }
      const next: Band = {
        repo,
        isWorktree,
        path,
        branch,
        changed,
        ahead,
        behind,
        model: prettyModel(model),
        tokens: usage.context.tokens ?? 0,
        window: usage.context.window,
        percent: usage.context.percent ?? 0,
        sessionId,
      }
      await update($, band, () => next)
    } while (isStale)
  } catch (err) {
    $.ui.log(`status-band: ${String(err)}`, { to: 'debug' })
  } finally {
    isBusy = false
  }
}


export const registerStatusBand = (on: Parameters<Register>[0]) => {
  on('session.measure', ($, e, next) => (void refresh($), next(e)))
  on('turn.complete', ($, e, next) => (void refresh($), next(e)))

  // Edits and shell commands are what move git status.
  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (e.tool === 'Bash' || e.tool === 'Edit' || e.tool === 'Write') void refresh($)
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    // First draw starts the periodic git refresh.
    if (!isTicking) {
      isTicking = true
      $.clock.every(GIT_REFRESH_MS, () => void refresh($))
    }
    const b = await read($, band)
    if (b === null) void refresh($)
    if (e.props.hasSurvey || b === null) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)

    const copy = (text: string, what: string) => (press: UiPressArgument) =>
      $.ui
        .copy({ text, surface: press.surface })
        .then(r => $.ui.toast(r.isCopied ? `Copied ${what}` : `Could not copy ${what}`))

    const modeLabel = b.isWorktree ? '𖣂 worktree' : '➤ root'
    const modeColor = b.isWorktree ? '#5fd787' : '#5fafff'
    const git =
      b.changed === 0 && b.ahead === 0 && b.behind === 0 ? (
        <Text color="#5fd787">✓ clean</Text>
      ) : (
        <Text>
          {b.changed > 0 && <Text color="#ffaf00">● {b.changed} changed</Text>}
          {b.ahead > 0 && <Text color="#ff5f5f"> ↑{b.ahead}</Text>}
          {b.behind > 0 && <Text color="#5fafff"> ↓{b.behind}</Text>}
        </Text>
      )
    const { on: filled, off: empty } = bar(b.percent)
    const sep = <Text dimColor>  │  </Text>

    // Tooltips: one row, each tip hidden until its trigger's hover scope lights.
    const tip = (scope: string, text: string) => (
      <Box key={`tip-${scope}`} display="none" hover={{ scope, display: 'flex' }}>
        <Text backgroundColor="#444444" color="#eeeeee"> {text} </Text>
      </Box>
    )

    return (
      <Box flexDirection="column">
        <Box key="tips">
          {tip('mode', `${b.isWorktree ? 'worktree' : 'root'}: ${b.path}  (click to copy)`)}
          {tip('session', `session ${b.sessionId}  (click to copy)`)}
        </Box>
        <Box key="row">
          <Text backgroundColor="#585858" color="#ffffff" bold> {b.repo} </Text>
          <Text> </Text>
          <Box key="mode" hover={{ scope: 'mode' }}>
            <Button
              key="mode-btn"
              plain
              onPress={copy(b.path, 'path')}
            >
              <Text color={modeColor}>{modeLabel}</Text>
            </Button>
          </Box>
          <Text>  </Text>
          {b.branch && <Text color="#d787d7">⎇ {b.branch}</Text>}
          <Text>  </Text>
          {git}
          {sep}
          <Text color="#d7af5f">◆</Text>
          <Text> {b.model}</Text>
          {sep}
          <Text color={barColor(b.percent)}>{filled}</Text>
          <Text dimColor>{empty}</Text>
          <Text>
            {' '}
            {fmt(b.tokens)}/{fmt(b.window)} <Text dimColor>{b.percent}%</Text>
          </Text>
          {sep}
          <Box key="session" hover={{ scope: 'session' }}>
            <Button key="session-btn" plain onPress={copy(b.sessionId, 'session ID')}>
              <Text backgroundColor="#444444" color="#bcbcbc"> Session ID ⧉ </Text>
            </Button>
          </Box>
        </Box>
      </Box>
    )
  })
}
