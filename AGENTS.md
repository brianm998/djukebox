## Filing work for the pipeline

If you file a task that already contains the plan (the files to change, the
approach and the acceptance criteria), mark it explored so the pipeline skips
its exploring step: pass `explored: true` to `file_proposal`, or `--explored` to
`mason task add`, or put `explored: true` in the task's front matter. Only do
this when the task body really is the plan. Run `mason help filing` for details.
