#!/bin/bash

# Milestone Variables
MILESTONE_TITLE=""
MILESTONE_DURATION="14d"

# GitHub Variables
GITHUB_USERNAME=""
GITHUB_TOKEN=""
GITHUB_ORG_NAME=""
GITHUB_REPOS=(
)

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
