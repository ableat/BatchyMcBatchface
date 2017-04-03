## Requirements

### Tools
[jq](https://stedolan.github.io/jq/)
[curl](https://curl.haxx.se)

### Accounts
[GitHub Account](https://github.com/join)
[GitHub Account Personal API Token](https://github.com/blog/1509-personal-api-tokens)
[GitHub Organization](https://github.com/blog/674-introducing-organizations)

## Script Setup

Some values in the `updater.sh` file need to be updated to reflect your organization's repositories.

* `MILESTONE_TITLE` -- This is the name of the milestone. (e.g. *Sprint 2* could be the name of the milestone, if your team is using Scrum)
* `MILESTONE_DURATION` -- This is the duration (from today) that the milestone is due. (e.g. If today is April 3 and the duration is set to *14d*, the due date will be April 17)
*  `GITHUB_USERNAME` -- The username of the github user that created a Personal API Token. This will be used to authenticate the user and use the GitHub API.
* `GITHUB_TOKEN` -- The [GitHub Account Personal API Token](https://github.com/blog/1509-personal-api-tokens) that gives this user access to the GitHub Repositories in the script.
* `GITHUB_ORG_NAME` -- The name of the organization that will receive the batch milestone update.
* `GITHUB_REPOS` -- An array of strings of the names of the GitHub Repositories.

## Usage

```
sh updater.sh
```
