export type Band = {
  repo: string
  isWorktree: boolean
  path: string
  branch: string
  changed: number
  ahead: number
  behind: number
  model: string
  tokens: number
  window: number
  percent: number
  sessionId: string
}

declare module 'claude-code' {
  interface PluginState {
    workbench: { statusBand: Band | null }
  }
}
