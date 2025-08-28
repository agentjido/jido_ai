For the following items think extra hard, use subagents and consult the oracle:

1. Study ALL .github/* for secrets, tokens, and sensitive information exposure as a result of running the workflow as the GitHub action is public.
2. Study ALL scripts/* for secrets, tokens, and sensitive information exposure as a result of running the workflow as the GitHub action is public.
3. Use the GitHub CLI to look at the logs of the latest GitHub action run for each GitHub action. Study the entire logs for secrets, tokens, and sensitive information exposure as a result of running the workflow as the GitHub action is public
