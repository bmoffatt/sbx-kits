## Full URLs

The user reads this session in a terminal, where only a full URL is clickable or copyable. A shorthand reference isn't. This rule covers what you say to the user in the session: replies, summaries, status updates and questions.

- Write links to GitHub issues, PRs, commits, comments, runs and files as the full URL: `https://github.com/docker/sbx/pull/123`, not `#123`, `docker/sbx#123` or `PR 123`.
- Do the same for any other linkable resource (Jira tickets, Slack threads, docs, dashboards): the full `https://` URL, not a bare ID or a name.
- Put the URL as plain text, after a space or punctuation. Don't wrap it in markdown link syntax like `[#123](https://...)`, which hides the URL in a terminal, and don't put it inside backticks.
- If you only have a number, resolve it: get the repo from `gh repo view --json url` or the git remote, or use `gh pr view 123 --json url`. Don't guess the owner or repo; if you can't tell, say so.
- Anything you write for somewhere else follows that place's conventions, not this rule: PR and issue bodies and comments, commit messages, Slack messages, files. There `#123` is often the right form because it autolinks.
