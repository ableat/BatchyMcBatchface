#!/bin/bash

DYING=0

RED="\033[0;31m"
CYAN="\033[0;36m"
WHITE="\033[0;37m"
ORANGE="\033[0;33m"
PURPLE="\033[0;35m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m" #No color

CONFIG="config.json"

# Milestone Variables
MILESTONE_TITLE=""
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

[[ -z "${GITHUB_USERNAME// }" ]] && GITHUB_USERNAME=$(jq -r .github.user_name "${CONFIG}")

[[ -z "${GITHUB_TOKEN// }" ]] && GITHUB_TOKEN=$(jq -r .github.api_token "${CONFIG}")

[[ -z "${GITHUB_ORG_NAME// }" ]] && GITHUB_ORG_NAME=$(jq -r .github.organization "${CONFIG}")

[[ -z "${MILESTONE_TITLE// }" ]] && MILESTONE_TITLE=$(jq -r .milestone.title "${CONFIG}")

[[ -z "${MILESTONE_DURATION// }" ]] && MILESTONE_DURATION=$(jq -r .milestone.duration "${CONFIG}")

[[ -z "${GITHUB_REPOS// }" ]] && GITHUB_REPOS=( $(jq -r '.github.repos | .[]' "${CONFIG}") )

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
    repo_response=$(curl -s -o /dev/null -w "%{http_code}" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}" -u "${gh_up}")
    if [ $repo_response -ne "200" ]; then
        _warn "${PURPLE}${gh_repo}${NC} repository does not exist. Skipping..."
    else
        _log "Updating ${PURPLE}${gh_repo}${NC} repository..."

        ## Get all Open + Ready/In Progress Issues
        repo_issues_ready=$(curl -s "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=ready" -u "${gh_up}" | jq .[].number)
        repo_issues_in_progress=$(curl -s "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=in%20progress" -u "${gh_up}" | jq .[].number)
        repo_issues_to_move=( ${repo_issues_ready[@]} ${repo_issues_in_progress[@]} )

        milestone_number=$(curl -s -X "POST" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/milestones" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d "{ \"title\": \"${MILESTONE_TITLE}\", \"state\": \"open\", \"description\": \"Welcome to ${MILESTONE_TITLE}. We have all kinds of cool things in store...\", \"due_on\": \"${milestone_due_date}\" }"  | jq .number)
        previous_milestone_number=$((milestone_number-1))
        [[ $previous_milestone_number -lt 0 ]] && previous_milestone_number=0
        _success "Created ${CYAN}${MILESTONE_TITLE}${NC} milestone"

        ## Add Ready and In Progress Issues to the New Milestone
        for repo_issue in ${repo_issues_to_move[@]}; do
            repo_milestone_number=$(curl -s -X "PATCH" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues/${repo_issue}" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d $"{ \"milestone\": ${milestone_number} }" | jq .milestone.number)
            [[ $repo_milestone_number -eq $milestone_number ]] && _success "Added ${WHITE}#${repo_issue}${NC} to ${CYAN}${MILESTONE_TITLE}${NC}" || _warn "Did not add ${WHITE}#${repo_issue}${NC} to ${CYAN}${MILESTONE_TITLE}${NC} :("
        done

        # Close the previous milestone :)
        if [[ $previous_milestone_number -gt 0 ]]; then
            milestone_state=$(curl -s -X "PATCH" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/milestones/${previous_milestone_number}" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d $"{ \"state\": \"closed\" }" | jq -r .state)
            [[ ${milestone_state} -eq "closed" ]] && _success "${ORANGE}Milestone #${previous_milestone_number}${NC} closed" || _warn "${ORANGE}Milestone #${previous_milestone_number}${NC} was not closed :("
        fi

        _success "Updated ${PURPLE}${gh_repo}${NC} repository :)"
    fi
done
