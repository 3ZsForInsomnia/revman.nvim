# revman.nvim

An easier way to track multiple PRs that you are reviewing

## TODO

- Add new PRs
  - Track last comment/commit viewed timestamps
  - Track creator info, PR age, opening frequency, last opened, review status, review history
  - Allow personal notes stored just locally/in DB
- Set status of PR
  - Statuses: waiting for review, waiting for updates/replies, approved/ready for merging, merged
- List PRs
  - Show all data referenced above
  - Preferably steal some of how Octo previews PRs as well
    - https://github.com/pwntester/octo.nvim/blob/master/lua/octo/pickers/telescope/previewers.lua
  - Don't show merged PRs or PRs that are ready for merging with no changes in comments or commits since approval
  - Show PR status in CI/CD

Use sqlite in xdg state directory to store data
- Tables for Repos, PRs, notes, and statuses?

Additional features - I don't really know if I care about this
- PR work types
  - Use config to define categories of work and folders and filetypes that match them
  - E.g. "PR is n% frontend, m% frontend tooling"
