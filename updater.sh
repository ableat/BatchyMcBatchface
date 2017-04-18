#!/bin/bash

DYING=0

## Constants
F_BLK="\033[0;30m"
F_RED="\033[0;31m"
F_GRN="\033[0;32m"
F_ORG="\033[0;33m"
F_BLU="\033[0;34m"
F_PUR="\033[0;35m"
F_CYN="\033[0;36m"
F_LGRY="\033[0;37m"
F_DGRY="\033[1;30m"
F_LRED="\033[1;31m"
F_LGRN="\033[1;32m"
F_YEL="\033[1;33m"
F_LBLU="\033[1;34m"
F_LPUR="\033[1;35m"
F_LCYN="\033[1;36m"
F_WHT="\033[0;37m"
F_CLR="\033[0m"

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
    _log "${F_YEL}WARNING:${F_CLR} ${@}"
}

_success() {
    _log "${F_GRN}SUCCESS:${F_CLR} ${@}"
}

_die() {
    _log "${F_RED}FATAL:${F_CLR} ${@}"
    _log "${F_RED}FATAL:${F_CLR} Going down in flames!"

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

$(echo -e "Welcome to the ${F_CYN}GitHub Batch Milestone Updater${F_CLR}")

This program allows ends users of organizations to
update specified repositories with new milestones

Please refer to the usage below

$(echo -e "${F_WHT}usage:${F_CLR} ./${0##*/} ${F_ORG}<command>${F_CLR}")

$(echo -e "${F_YEL}commands:${F_CLR}")
$(echo -e "    ${F_WHT}-h${F_CLR}                     display usage")
$(echo -e "    ${F_WHT}-u${F_CLR} ${F_ORG}username${F_CLR}            set github user name (${F_PUR}-u binarybeard${F_CLR})")
$(echo -e "    ${F_WHT}-t${F_CLR} ${F_ORG}token${F_CLR}               set github api token (${F_PUR}-t \"1234567890abcdefg\"${F_CLR})")
$(echo -e "    ${F_WHT}-o${F_CLR} ${F_ORG}organization${F_CLR}        set github organization (${F_PUR}-o Acme${F_CLR})")
$(echo -e "    ${F_WHT}-r${F_CLR} ${F_ORG}repo1,repo2,etc${F_CLR}     set github repos (${F_PUR}-r awesome-repo-1,cool_repo_2${F_CLR})")
$(echo -e "    ${F_WHT}-m${F_CLR} ${F_ORG}milestone${F_CLR}           set milestone title (${F_PUR}-m \"Sprint 7\"${F_CLR})")
$(echo -e "    ${F_WHT}-d${F_CLR} ${F_ORG}duration${F_CLR}            set milestone duration (${F_PUR}-d 7d${F_CLR})")

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

# Kill everything!
[[ -z "${GITHUB_USERNAME}" ]] && _die "GitHub username is blank"
[[ -z "${GITHUB_TOKEN}" ]] && _die "GitHub API token is blank"
[[ -z "${GITHUB_ORG_NAME}" ]] && _die "GitHub organization name is blank"
[[ -z "${MILESTONE_TITLE}" ]] && _die "GitHub new milestone title is blank"
[[ -z "${MILESTONE_DURATION}" ]] && _die "GitHub milestone duration is blank"
[[ ${#GITHUB_REPOS[@]} -lt 1 ]] && _die "GitHub repos are empty"


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
        _warn "${F_PUR}${gh_repo}${F_CLR} repository does not exist. Skipping..."
    else
        _log "Updating ${F_PUR}${gh_repo}${F_CLR} repository..."

        ## Get all Open + Ready/In Progress Issues
        repo_issues_ready=$(curl -s "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=ready" -u "${gh_up}" | jq .[].number)
        repo_issues_in_progress=$(curl -s "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=in%20progress" -u "${gh_up}" | jq .[].number)
        repo_issues_to_move=( ${repo_issues_ready[@]} ${repo_issues_in_progress[@]} )

        milestone_number=$(curl -s -X "POST" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/milestones" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d "{ \"title\": \"${MILESTONE_TITLE}\", \"state\": \"open\", \"description\": \"Welcome to ${MILESTONE_TITLE}. We have all kinds of cool things in store...\", \"due_on\": \"${milestone_due_date}\" }"  | jq .number)
        previous_milestone_number=$((milestone_number-1))
        [[ $previous_milestone_number -lt 0 ]] && previous_milestone_number=0
        _success "Created ${F_CYN}${MILESTONE_TITLE}${F_CLR} milestone"

        ## Add Ready and In Progress Issues to the New Milestone
        for repo_issue in ${repo_issues_to_move[@]}; do
            repo_milestone_number=$(curl -s -X "PATCH" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/issues/${repo_issue}" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d $"{ \"milestone\": ${milestone_number} }" | jq .milestone.number)
            [[ $repo_milestone_number -eq $milestone_number ]] && _success "Added ${F_WHT}#${repo_issue}${F_CLR} to ${F_CYN}${MILESTONE_TITLE}${F_CLR}" || _warn "Did not add ${F_WHT}#${repo_issue}${F_CLR} to ${F_CYN}${MILESTONE_TITLE}${F_CLR} :("
        done

        # Close the previous milestone :)
        if [[ $previous_milestone_number -gt 0 ]]; then
            milestone_state=$(curl -s -X "PATCH" "${gh_repos_url}/${GITHUB_ORG_NAME}/${gh_repo}/milestones/${previous_milestone_number}" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d $"{ \"state\": \"closed\" }" | jq -r .state)
            [[ ${milestone_state} -eq "closed" ]] && _success "${F_ORG}Milestone #${previous_milestone_number}${F_CLR} closed" || _warn "${F_ORG}Milestone #${previous_milestone_number}${F_CLR} was not closed :("
        fi

        _success "Updated ${F_PUR}${gh_repo}${F_CLR} repository :)"
    fi
done
