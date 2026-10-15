import type { Register } from 'claude-code'

import { registerStatusBand } from './status-band'

const DIR = '/tmp/claude-rename'

// Blocks on a named pipe per session: no polling, a write renames at once.
// External use: echo "new title" > /tmp/claude-rename/<session-id>
export const register: Register = on => {
  registerStatusBand(on)

  on('session.start', async ($, e, next) => {
    const fifo = `${DIR}/${await $.session.id()}`
    const reader = $.process.spawn({
      argv: ['sh', '-c', 'mkdir -p "$1"; [ -p "$2" ] || mkfifo "$2"; while :; do cat "$2"; done', '_', DIR, fifo],
    })
    void (async () => {
      for await (const { stream, text } of reader) {
        if (stream !== 'stdout') continue
        for (const title of text.split('\n').map(s => s.trim()).filter(Boolean)) {
          await $.command.run({ command: 'rename', args: title }).catch(err => $.ui.toast(`rename: ${String(err)}`))
        }
      }
    })()
    return next(e)
  })
}
