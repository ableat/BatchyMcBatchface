#!/bin/bash

DYING=0

RED="\033[0;31m"
GREEN="\033[32m"
YELLOW="\033[33m"
NC="\033[0m" #No color

CONFIG="config.json"

# Milestone Variables
#MILESTONE_TITLE=""
MILESTONE_DURATION="14d"

# GitHub Variables
GITHUB_USERNAME=""
GITHUB_TOKEN=""
GITHUB_ORG_NAME=""
GITHUB_REPOS=(
)

_log() {
    echo -e ${0##*/}: "${@}" 1>&2
}

_warn() {
    _log "${YELLOW}WARNING:${NC} ${@}"
}

_success() {
    _log "${GREEN}SUCCESS:${NC} ${@}"
}

_die() {
    _log "${RED}FATAL:${NC} ${@}"
    if [ "${DYING}" -eq 0 ]; then
        DYING=1
    fi

    exit 1
}

dependencies=(
    "jq"
    "curl"
)
for program in "${dependencies[@]}"; do
    command -v $program >/dev/null 2>&1 || {
        _die "${program} is not installed."
    }
done

_usage() {
cat << EOF

${0##*/} [-h] [-b basename] -- program to automate sprint milestones for agile development
where:
    -u  set github user name
    -t  set github api token
    -o  set github organization
    -r  set github repos
    -m  set milestone title
    -d  set milestone duration

EOF
}

#Create config file if it doesn't exist
if [ ! -f "${CONFIG}" ]; then
cat << EOF > "${CONFIG}"
{
    "github": {
        "user_name": "",
        "api_token": "",
        "organization": "",
        "repos": []
    },
    "milestone": {
        "title": "",
        "duration": ""
    }
}
EOF
fi

[[ -z "${GITHUB_USERNAME// }" ]] && GITHUB_USERNAME=$(cat "${CONFIG}" | jq .github.user_name | tr -d '"')

[[ -z "${GITHUB_TOKEN// }" ]] && GITHUB_TOKEN=$(cat "${CONFIG}" | jq .github.api_token | tr -d '"')

[[ -z "${GITHUB_ORG_NAME// }" ]] && GITHUB_ORG_NAME=$(cat "${CONFIG}" | jq .github.organization | tr -d '"')

[[ -z "${MILESTONE_TITLE// }" ]] && MILESTONE_TITLE=$(cat "${CONFIG}" | jq .milestone.title | tr -d '"')

[[ -z "${MILESTONE_DURATION// }" ]] && MILESTONE_DURATION=$(cat "${CONFIG}" | jq .milestone.duration | tr -d '"')

[[ -z "${GITHUB_REPOS// }" ]] && GITHUB_REPOS=$(cat "${CONFIG}" | jq .github.repos | sed -r 's/(\[|\])//g' | tr -d ',')

while getopts ':h u: t: o: r: m: d:' option; do
    case "${option}" in
        h|\?) _usage
           exit 0
           ;;
        u) GITHUB_USERNAME="${OPTARG}"
           ;;
        t) GITHUB_TOKEN="${OPTARG}"
           ;;
        o) GITHUB_ORG_NAME="${OPTARG}"
           ;;
        r) GITHUB_REPOS="${OPTARG}"
           ;;
        m) MILESTONE_TITLE="${OPTARG}"
           ;;
        d) MILESTONE_DURATION="${OPTARG}"
           ;;
        :) printf "missing argument for -%s\n" "${OPTARG}"
           _usage
           exit 1
           ;;
    esac
done
shift $((OPTIND - 1))

# Calculated Variables
milestone_due_date=$(date -j -v+${MILESTONE_DURATION} -u +"%Y-%m-%dT14:00:00Z")

gh_repos_url="https://api.github.com/repos"
gh_up="${GITHUB_USERNAME}:${GITHUB_TOKEN}"

## List Open and Ready Issues
for gh_repo in "${GITHUB_REPOS[@]}"; do
    echo "Updating ${gh_repo} repository..."

    ## Get all Open + Ready/In Progress Issues
    repo_issues_ready=$(curl -s "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=ready" -u "${gh_up}" | jq .[].number)
    repo_issues_in_progress=$(curl -s "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=in%20progress" -u "${gh_up}" | jq .[].number)
    repo_issues_to_move=( ${repo_issues_ready[@]} ${repo_issues_in_progress[@]} )

    ## Create a new Milestone
    echo "Creating ${MILESTONE_TITLE}..."
    milestone_number=$(curl -s -X "POST" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/milestones" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d "{ \"title\": \"${MILESTONE_TITLE}\", \"state\": \"open\", \"description\": \"Welcome to ${MILESTONE_TITLE}. We have all kinds of cool things in store...\", \"due_on\": \"${milestone_due_date}\" }"  | jq .number)
    previous_milestone_number=$((milestone_number-1))
    [[ $previous_milestone_number -lt 0 ]] && previous_milestone_number=0
    echo "Finished creating ${MILESTONE_TITLE}"

    ## Add Ready and In Progress Issues to the New Milestone
    for repo_issue in ${repo_issues_to_move[@]}; do
        echo "Adding issue #${repo_issue} to ${MILESTONE_TITLE}..."
        repo_milestone_number=$(curl -s -X "PATCH" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues/${repo_issue}" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d $"{ \"milestone\": ${milestone_number} }" | jq .milestone.number)
        [[ $repo_milestone_number -eq $milestone_number ]] && echo "Issue #${repo_issue} added to ${MILESTONE_TITLE} sucessfully" || echo "Issue #${repo_issue} was not added to ${MILESTONE_TITLE}. What happened?"
    done

    # Close the previous milestone :)
    if [[ $previous_milestone_number -gt 0 ]]; then
        echo "Closing milestone #${previous_milestone_number}..."
        milestone_state=$(curl -s -X "PATCH" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/milestones/${previous_milestone_number}" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d $"{ \"state\": \"closed\" }" | jq -r .state)
        [[ ${milestone_state} -eq "closed" ]] && echo "Milestone #${previous_milestone_number} closed sucessfully" || echo "Milestone #${previous_milestone_number} was not closed :("
    fi

    echo "Completed updating ${gh_repo} repository :)\n"
done
