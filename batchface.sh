#!/bin/bash

DYING=0
VERBOSE=0
DRY_RUN=0

# Colors are declared in this fashion to ensure compatibility with older versions of bash
colors=(
    RED_COLOR,"\"\033[0;31m\""
    GRN_COLOR,"\"\033[0;32m\""
    ORG_COLOR,"\"\033[0;33m\""
    BLU_COLOR,"\"\033[0;34m\""
    PUR_COLOR,"\"\033[0;35m\""
    YEL_COLOR,"\"\033[1;33m\""
    LBLU_COLOR,"\"\033[1;34m\""
    LPUR_COLOR,"\"\033[1;35m\""
    LCYN_COLOR,"\"\033[1;36m\""
    WHT_COLOR,"\"\033[0;37m\""
    CLR_COLOR,"\"\033[0m\""
    LGRN_COLOR,"\"\033[1;32m\""
    CYN_COLOR,"\"\033[0;36m\""
    LGRY_COLOR,"\"\033[0;37m\""
    BLK_COLOR,"\"\033[0;30m\""
    DGRY_COLOR,"\"\033[1;30m\""
    LRED_COLOR,"\"\033[1;31m\""
)

_setColors() {
    for color in "${colors[@]}"; do
        IFS=', ' read -r -a pseudo_arr <<< "$color"
        eval "${pseudo_arr[0]}=${pseudo_arr[1]}"
    done
    _setDescriptiveColors
}

_blankColors() {
    for color in "${colors[@]}"; do
        IFS=', ' read -r -a pseudo_arr <<< "$color"
        eval "${pseudo_arr[0]}=''"
    done
    _setDescriptiveColors
}

_setDescriptiveColors() {
    # Help colors
    c_title=$LCYN_COLOR; c_usage=$CYN_COLOR; c_command_title=$YEL_COLOR; c_command=$WHT_COLOR;
    c_command_variable=$ORG_COLOR; c_command_example=$PUR_COLOR

    # Log colors
    c_url=$CYN_COLOR; c_url_action=$LGRN_COLOR; c_gh_label=$LCYN_COLOR; c_repo=$ORG_COLOR;
    c_milestone=$PUR_COLOR; c_bad_response=$RED_COLOR; c_variable=$GRN_COLOR; c_issue=$ORG_COLOR

    # Deep log colors
    c_success=$GRN_COLOR; c_warning=$YEL_COLOR; c_fatal=$RED_COLOR; c_debug=$WHT_COLOR
}

# Color output
_setColors

# Config file path
CONFIG="config.json"

gh_api_url="https://api.github.com"
gh_ep_repos="${gh_api_url}/repos"
gh_ep_users="${gh_api_url}/users"
gh_ep_user="${gh_api_url}/user"
gh_ep_org="${gh_api_url}/orgs"

# Milestone Variables
MILESTONE_TITLE=""
MILESTONE_DURATION="14"

# GitHub Variables
GITHUB_USERNAME=""
GITHUB_TOKEN=""
GITHUB_ORG_NAME=""
declare -a GITHUB_REPOS

_log() {
    echo -e ${0##*/}: "${@}" 1>&2
}

_debug() {
    if [ "${VERBOSE}" -eq 1 ]; then
        _log "${c_debug}DEBUG:${CLR_COLOR} ${@}"
    fi
}

_warn() {
    _log "${c_warning}WARNING:${CLR_COLOR} ${@}"
}

_success() {
    _log "${c_success}SUCCESS:${CLR_COLOR} ${@}"
}

_die() {
    _log "${c_fatal}FATAL:${CLR_COLOR} ${@}"
    _log "${c_fatal}FATAL:${CLR_COLOR} Going down in flames!"

    if [ "${DYING}" -eq 0 ]; then
        DYING=1
    fi

    exit 1
}

# Check if dependencies are installed
dependencies=(
    "jq"
    "curl"
)

for program in "${dependencies[@]}"; do
    command -v $program >/dev/null 2>&1 || _die "${program} is not installed."
done

# Help text
_usage() {
cat << EOF
$(echo -e "Welcome to ${c_title}Batchy McBatchface${CLR_COLOR}")

This program allows end users of GitHub Organizations to update specified repositories with identical milestones

NOTE: A config file is generated when the program is first run. Command line arguments trump config file parameters. The config file needs to be located in the same location as the script.

$(echo -e "${c_usage}usage:${CLR_COLOR} ./${0##*/} ${c_command_title}[option] <command>${CLR_COLOR}")

$(echo -e "${c_command_title}options:${CLR_COLOR}")
$(echo -e "    ${c_command}-v${CLR_COLOR}                     verbose output")
$(echo -e "    ${c_command}-n${CLR_COLOR}                     no color output")
$(echo -e "    ${c_command}-x${CLR_COLOR}                     dry run")

$(echo -e "${c_command_title}commands:${CLR_COLOR}")
$(echo -e "    ${c_command}-h${CLR_COLOR}                     display this help message")
$(echo -e "    ${c_command}-u${CLR_COLOR} ${c_command_variable}username${CLR_COLOR}            set github user name (${c_command_example}-u binarybeard${CLR_COLOR})")
$(echo -e "    ${c_command}-t${CLR_COLOR} ${c_command_variable}token${CLR_COLOR}               set github api token (${c_command_example}-t \"1234567890abcdefg\"${CLR_COLOR})")
$(echo -e "    ${c_command}-o${CLR_COLOR} ${c_command_variable}organization${CLR_COLOR}        set github organization (${c_command_example}-o Acme${CLR_COLOR})")
$(echo -e "    ${c_command}-r${CLR_COLOR} ${c_command_variable}repo1,repo2,etc${CLR_COLOR}     set github repos (${c_command_example}-r awesome-repo-1,cool_repo_2${CLR_COLOR})")
$(echo -e "    ${c_command}-m${CLR_COLOR} ${c_command_variable}milestone${CLR_COLOR}           set milestone title (${c_command_example}-m \"Sprint 7\"${CLR_COLOR})")
$(echo -e "    ${c_command}-d${CLR_COLOR} ${c_command_variable}duration${CLR_COLOR}            set milestone duration in days (${c_command_example}-d 7${CLR_COLOR})")

EOF
}

# Create config file if it doesn't exist
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
else
    # If it does, load everything
    GITHUB_USERNAME=$(jq -r .github.user_name "${CONFIG}")
    GITHUB_TOKEN=$(jq -r .github.api_token "${CONFIG}")
    GITHUB_ORG_NAME=$(jq -r .github.organization "${CONFIG}")
    MILESTONE_TITLE=$(jq -r .milestone.title "${CONFIG}")
    MILESTONE_DURATION=$(jq -r .milestone.duration "${CONFIG}")
    GITHUB_REPOS=( $(jq -r '.github.repos | .[]' "${CONFIG}") )
fi

# Getting options
while getopts ':n :h u: t: o: r: m: d: :v :x' option; do
    case "${option}" in
        n) _blankColors
           ;;
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
        x) DRY_RUN=1
           ;;
        v) VERBOSE=1
           ;;
        :) printf "missing argument for -%s\n" "${OPTARG}"
           _usage
           exit 1
           ;;
    esac
done
shift $((OPTIND - 1))

# Kill everything (if it's not there)!
_debug "Checking to see if variables exist..."
[[ -z "${GITHUB_USERNAME// }" ]] && _die "GitHub username is blank"
_debug "GitHub username exists"
[[ -z "${GITHUB_TOKEN// }" ]] && _die "GitHub API token is blank"
_debug "GitHub API token exists"
[[ -z "${GITHUB_ORG_NAME// }" ]] && _die "GitHub organization name is blank"
_debug "GitHub organization name exists"
[[ -z "${MILESTONE_TITLE// }" ]] && _die "GitHub new milestone title is blank"
_debug "Milestone title exists"
[[ -z "${MILESTONE_DURATION// }" ]] && _die "GitHub milestone duration is blank"
_debug "Milestone duration exists"
[[ ${#GITHUB_REPOS[@]} -lt 1 ]] && _die "GitHub repos are empty"
_debug "Repository array is not empty"

if [ "${DRY_RUN}" -eq 1 ]; then
    # Do something magical
fi

# Validate setting variables
_debug "Validating setting variables..."
! [[ "${MILESTONE_DURATION}" =~ ^[0-9] ]] && _die "Milestone duration does not match ^[0-9] regular expression"
_debug "Milestone duration has been validated"

# Create the GitHub username:token
gh_up="${GITHUB_USERNAME}:${GITHUB_TOKEN}"

# Kill everything... if we can't API it! (Yes, API is a verb)
# API is not a verb.......
_debug "Checking ${c_url}${gh_ep_users}/${GITHUB_USERNAME}${CLR_COLOR} for good response..."
gh_usr_res=$(curl -s -o /dev/null -w "%{http_code}" "${gh_ep_users}/${GITHUB_USERNAME}")
[[ $gh_usr_res -ne "200" ]] && _die "GitHub username does not exist"
_debug "Received good response from ${c_url}${gh_ep_users}/${GITHUB_USERNAME}${CLR_COLOR}"

_debug "Checking ${c_url}${gh_ep_org}/${GITHUB_ORG_NAME}${CLR_COLOR} for good response..."
gh_org_res=$(curl -s -o /dev/null -w "%{http_code}" "${gh_ep_org}/${GITHUB_ORG_NAME}")
[[ $gh_org_res -ne "200" ]] && _die "GitHub organization does not exist"
_debug "Received good response from ${c_url}${gh_ep_org}/${GITHUB_ORG_NAME}${CLR_COLOR}"

_debug "Checking ${c_url}${gh_ep_user}${CLR_COLOR} for good response..."
gh_ath_res=$(curl -s -o /dev/null -w "%{http_code}" "${gh_ep_user}" -u "${gh_up}")
[[ $gh_ath_res -ne "200" ]] && _die "GitHub user is not authenticated"
_debug "Received good response from ${c_url}${gh_ep_user}${CLR_COLOR}"

# Calculated Variables
milestone_due_date=$(date -j -v+"${MILESTONE_DURATION}d" -u +"%Y-%m-%dT14:00:00Z")
_debug "Milestone due date is set to ${c_variable}${milestone_due_date}${CLR_COLOR}"

repo_count_total=0
repo_count_success=0

# List Open and Ready Issues
for gh_repo in "${GITHUB_REPOS[@]}"; do
    ((repo_count_total+=1))
    _debug "Checking ${c_url}${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}${CLR_COLOR} for good response..."
    repo_response=$(curl -s -o /dev/null -w "%{http_code}" "${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}" -u "${gh_up}")
    if [ $repo_response -ne "200" ]; then
        _debug "${c_url}${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}${CLR_COLOR} received a ${c_bad_response}${repo_response} response${CLR_COLOR}"
        _warn "${c_repo}${gh_repo}${CLR_COLOR} repository does not exist. Skipping..."
    else
        _debug "Received good response from ${c_url}${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}${CLR_COLOR}"
        _log "Updating ${c_repo}${gh_repo}${CLR_COLOR} repository..."

        # Get all Open + Ready/In Progress Issues
        _debug "Getting ${c_gh_label}ready${CLR_COLOR} issues from ${c_url}${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=ready${CLR_COLOR}"
        repo_issues_ready=$(curl -s "${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=ready" -u "${gh_up}" | jq .[].number)
        _debug "Getting ${c_gh_label}in progress${CLR_COLOR} issues from ${c_url}${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=in%20progress${CLR_COLOR}"
        repo_issues_in_progress=$(curl -s "${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/issues?state=open&labels=in%20progress" -u "${gh_up}" | jq .[].number)
        repo_issues_to_move=( ${repo_issues_ready[@]} ${repo_issues_in_progress[@]} )

        _debug "Creating ${c_milestone}${MILESTONE_TITLE}${CLR_COLOR} milestone with ${c_url_action}POST${CLR_COLOR} ${c_url}${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/milestones${CLR_COLOR}"
        milestone_number=$(curl -s -X "POST" "${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/milestones" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d "{ \"title\": \"${MILESTONE_TITLE}\", \"state\": \"open\", \"description\": \"Welcome to ${MILESTONE_TITLE}. We have all kinds of cool things in store...\", \"due_on\": \"${milestone_due_date}\" }"  | jq .number)
        previous_milestone_number=$((milestone_number-1))
        [[ $previous_milestone_number -lt 0 ]] && previous_milestone_number=0
        _debug "${c_milestone}Milestone #${previous_milestone_number}${CLR_COLOR} is the current (to be closed) milestone number"
        _success "Created ${c_milestone}${MILESTONE_TITLE}${CLR_COLOR} milestone"

        # Add Ready and In Progress Issues to the New Milestone
        for repo_issue in ${repo_issues_to_move[@]}; do
            _debug "Adding issue ${c_issue}#${repo_issue}${CLR_COLOR} to ${c_milestone}${MILESTONE_TITLE}${CLR_COLOR} milestone with ${c_url_action}PATCH${CLR_COLOR} ${c_url}${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/issues/${repo_issue}${CLR_COLOR}"
            repo_milestone_number=$(curl -s -X "PATCH" "${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/issues/${repo_issue}" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d $"{ \"milestone\": ${milestone_number} }" | jq .milestone.number)
            [[ $repo_milestone_number -eq $milestone_number ]] && _success "Added issue ${c_issue}#${repo_issue}${CLR_COLOR} to ${c_milestone}${MILESTONE_TITLE}${CLR_COLOR} milestone" || _warn "Did not add issue ${c_issue}#${repo_issue}${CLR_COLOR} to ${c_milestone}${MILESTONE_TITLE}${CLR_COLOR} milestone :("
        done

        # Close the previous milestone :)
        if [[ $previous_milestone_number -gt 0 ]]; then
            _debug "Closing ${c_milestone}milestone #${previous_milestone_number}${CLR_COLOR} with ${c_url_action}PATCH${CLR_COLOR} ${c_url}${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/milestones/${previous_milestone_number}${CLR_COLOR}"
            milestone_state=$(curl -s -X "PATCH" "${gh_ep_repos}/${GITHUB_ORG_NAME}/${gh_repo}/milestones/${previous_milestone_number}" -H "Content-Type: application/json; charset=utf-8" -u ${gh_up} -d $"{ \"state\": \"closed\" }" | jq -r .state)
            [[ ${milestone_state} -eq "closed" ]] && _success "Closed ${c_milestone}milestone #${previous_milestone_number}${CLR_COLOR} for the ${c_repo}${gh_repo}${CLR_COLOR} repository" || _warn "Failed to close ${c_milestone}milestone #${previous_milestone_number}${CLR_COLOR} for the ${c_repo}${gh_repo}${CLR_COLOR} repository :("
        fi
        ((repo_count_success+=1))
        _success "Updated ${c_repo}${gh_repo}${CLR_COLOR} repository with ${c_milestone}${MILESTONE_TITLE}${CLR_COLOR} milestone "
    fi
done

# How'd we do?
repo_success_percent=$((repo_count_success*100/repo_count_total))
repo_success_color=$c_success

if [[ $repo_success_percent -lt 100 && $repo_success_percent -gt 75 ]]; then
    repo_success_color=$c_warning
elif [[ $repo_success_percent -lt 76 ]]; then
    repo_success_color=$c_fatal
fi

if [[ $repo_success_percent -lt 100 ]]; then
    _warn "Only updated ${repo_success_color}${repo_success_percent}%${CLR_COLOR} (${c_variable}${repo_count_success}/${repo_count_total}${CLR_COLOR}) of repos with ${c_milestone}${MILESTONE_TITLE}${CLR_COLOR} milestone :|"
else
    _success "Updated ${repo_success_color}${repo_success_percent}%${CLR_COLOR} (${c_variable}${repo_count_success}/${repo_count_total}${CLR_COLOR}) of repos with ${c_milestone}${MILESTONE_TITLE}${CLR_COLOR} milestone :)"
fi
