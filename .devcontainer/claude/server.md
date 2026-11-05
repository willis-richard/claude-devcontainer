# This machine: GPU server

The code runs here at full size. I may run experiments myself or ask you to.

## Runs
- Before the first run of a session, check `python -c "import torch; print(torch.cuda.is_available())"`.
  If it prints False, stop and tell me: do not run on CPU.
- Start long jobs in their own tmux window (`tmux new-window -n <run>`), writing to
  outputs/<run>/. Never wait on a long job in the foreground.
- Report results from the run's own logs and output files, not from memory or console
  scrollback.
- You may fix bugs that stop a run. Do not change the method, the metric, the data or the
  budget to make a run succeed: stop and report instead. Record every change and its
  reason in docs/decisions.md.
- Stop at the project's checkpoints. When you are blocked, say clearly that you are
  waiting for me and stop: the server may shut itself down when idle.

## Git
- Start new work from the default branch:
  `git fetch origin && git switch -c server/<topic> origin/main`.
- Commit there, never on main. I fetch from this machine over SSH.

## Disk
- Before a run that writes checkpoints, check `df -h /workspace`; ask me if the run
  would leave under 20% free.
- Delete only what you created and no longer need (smoke tests, failed runs). Ask before
  deleting anything else.
