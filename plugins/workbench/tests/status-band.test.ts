import { expect, mock, test } from 'claude-code/testing'

const PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 6,
  bodyColumns: 120,
  scroll: { offset: 0, bodyRows: 6 },
  view: {},
} as never

const GIT = (isWorktree: boolean) => (argv: readonly string[]) => {
  if (argv.includes('rev-parse')) {
    const out = isWorktree
      ? '/w/hq-wt\n/r/hq/.git/worktrees/wt\n/r/hq/.git\n'
      : '/r/hq\n/r/hq/.git\n/r/hq/.git\n'
    return { exitCode: 0, stdout: out, stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
  }
  const out = '# branch.head feat/x\n# branch.ab +1 -0\n1 .M N... 100644 100644 100644 a b f.ts\n? new.ts\n'
  return { exitCode: 0, stdout: out, stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
}

for (const isWorktree of [false, true]) {
  test(`band shows ${isWorktree ? 'worktree' : 'root'} badge, git summary and copies on press`, async ($, on) => {
    const copied: string[] = []
    const clock = mock.clock(on)
    on('session.cwd', () => ({ value: '/r/hq' }))
    on('session.model', () => ({ value: 'claude-sonnet-5-5' }))
    on('session.id', () => ({ value: 'sess-123' }))
    on('session.usage', () => ({ value: { context: { tokens: 53_000, window: 1_000_000, percent: 5 } } }) as never)
    on('process.run', (_$, e) => ({ value: GIT(isWorktree)(e.argv) }) as never)
    on('ui.copy', (_$, e) => (copied.push(e.text), { value: { isCopied: true } }) as never)
    on('ui.toast', () => ({ value: {} }) as never)
    on('ui.log', () => ({ value: {} }) as never)
    on('ui.render', ($, e) => { const { Text } = $.ui.resolve(e); return h(Text, {}, ' ') as never })

    const ui = await $.ui.mount({ plugin: 'workbench', surface: 'terminal', component: 'AbovePrompt', props: PROPS })
    await clock.advance(1)
    const again = await $.ui.mount({ plugin: 'workbench', surface: 'terminal', component: 'AbovePrompt', props: PROPS })

    const shown = (await again.find({ type: 'Box', key: 'row' }))?.text ?? ''
    expect(shown).toContain('hq')
    expect(shown).toContain(isWorktree ? 'worktree' : 'root')
    expect(shown).toContain('feat/x')
    expect(shown).toContain('2 changed')
    expect(shown).toContain('↑1')
    expect(shown).toContain('Sonnet 5.5')
    expect(shown).toContain('53k/1.0M')

    await again.press({ key: 'mode-btn' })
    await again.press({ key: 'session-btn' })
    expect(copied).toEqual([isWorktree ? '/w/hq-wt' : '/r/hq', 'sess-123'])
    void ui
  })
}
