require "gitlab"
require "json"
require "awesome_print"
require "pry"
require "readline"
require "date"

CONFIG = {
    "project_id" => "<Enter your project id>",
    "GITLAB_API_PRIVATE_TOKEN" => "<Enter your private token>",
    "GITLAB_API_ENDPOINT" => "<Enter gitlab API url>",
    "team_name" => "testing"
}

RECURRING_ISSUES = [
  {
    'title' => 'Test | Meetings',
    'labels' => 'testing,p3,Planning,discussion',
    'time_estimate' => '1d'
  },
  {
    'title' => 'Test | Monitoring',
    'labels' => 'testing,p2,monitoring,Maintenance',
    'time_estimate' => '3h'
  }
]

Gitlab.configure do |config|
    config.endpoint       = CONFIG["GITLAB_API_ENDPOINT"]
    config.private_token  = CONFIG["GITLAB_API_PRIVATE_TOKEN"]
end

@current_user = Gitlab.user.to_h

def log_time
    current_branch = `git rev-parse --abbrev-ref HEAD`
    # It's assumed that branch name will have appended "/<issue-id>" e.g. for issue with ID 123, branch name should be "feature-xyz/123"
    issue_id = current_branch.split("/").last[0..-2].to_i

    issue = begin
        Gitlab.issue(CONFIG["project_id"], issue_id).to_h
    rescue Gitlab::Error::NotFound => e
        ap "Issue with id #{issue_id} does not exist. Your current branch is #{current_branch}"
        new_issue_id = Readline.readline("If you have issue id you want to use, please input: ", true)
        if new_issue_id.to_i > 0
            issue_id = new_issue_id
            retry
        else
            abort("Aborting! Invalid issue id")
        end
    end
    ap "Title: #{issue['title']}"
    ap "Estimated Time: #{issue["time_stats"]["human_time_estimate"]}, Spent Time: #{issue["time_stats"]["human_total_time_spent"]}"
    ap "URL: #{issue['web_url']}"
    time_spent = Readline.readline("Enter additional time spent e.g. (30m, 1h, 2h, 1h30m)", true)
    abort("Aborting! Invalid time spent.") if time_spent.to_s == ""
    # ISSUE["iid"] has the project issue id, don't mistake it for typo.
    ap Gitlab.add_time_spent_on_issue(CONFIG["project_id"], issue["iid"], time_spent)
end

def create_issue
    while true
        ap "Please fill in details to create issue for current project"
        title = Readline.readline("Title: ")
        estimated_time = Readline.readline("Estimated Time e.g. [1d, 1w, 30m, 2h]: ", true)
        assign_to_yourself = Readline.readline("Assign issue to yourself [y/n]:", true)
        options = {}
        options['labels'] = get_labels
        options['milestone_id'] = get_or_create_milestone['id']
        options['assignee_id'] = @current_user["id"] if assign_to_yourself.downcase == "y"
        created_issue = Gitlab.create_issue(CONFIG["project_id"], title, options).to_h
        Gitlab.estimate_time_of_issue(CONFIG["project_id"], created_issue["iid"], estimated_time)
        ap "Created issue at #{created_issue["web_url"]}"

        create_more = Readline.readline("Create more issue? [y/n]: ", true)
        break unless create_more.downcase == "y"
    end
end

def get_labels
  [
    get_priority, 
    get_sdlc_label, 
    get_current_week_label, 
    CONFIG['team_name'], 
    get_type_label
  ].join(",")
end

def get_priority
  allowed = ["P0","P1","P2","P3","P4","P5"]
  ans = Readline.readline("Enter priority, allowed: [#{allowed.join(",")}]: ", true)
  (allowed.include? ans) ? ans : get_priority
end

def get_sdlc_label
  allowed = {
    1 => 'Learning',
    2 => 'Planning',
    3 => 'Implementation',
    4 => 'Testing',
    5 => 'Maintenance',
    6 => 'review',
    7 => 'Deployment'
  }
  ap allowed
  ans = Readline.readline("Enter SDLC label e.g. 1, 2: ", true).to_i
  (allowed.keys.include? ans) ? allowed[ans] : get_sdlc_label
end

def get_current_week_label
  get_or_create_milestone['title']
end

def get_type_label
  allowed = {
    1 => 'bug',
    2 => 'feature',
    3 => 'enhancement',
    4 => 'discussion',
    5 => 'monitoring'
  }
  ap allowed
  ans = Readline.readline("Enter issue type label e.g. 1, 2: ", true).to_i
  (allowed.keys.include? ans) ? allowed[ans] : get_type_label
end

def get_or_create_milestone
  @get_milestone ||= begin
    title = Time.now.strftime('%Y-%V')
    current_milestone = Gitlab.milestones(CONFIG['project_id'], options = {title: title}).last
    return current_milestone.to_h unless current_milestone.nil?

    create_new_milestone(title)
  end
end

def create_new_milestone(title)
  current_day = Date.today
  start_of_week = current_day - current_day.cwday + 1
  end_of_week = start_of_week + 4
  options[:due_date] = end_of_week
  options[:start_date] = start_of_week
  Gitlab.create_milestone(CONFIG['project_id'], title, options = {}).to_h
end

def create_recurring_issues
  action = Readline.readline("This actions will create configured recurring issues. #{RECURRING_ISSUES}. Are you sure you want to continue?[y/n]", true)
  abort if action.downcase != 'y'

  RECURRING_ISSUES.each do |issue|
    options = {}
    options['labels'] = issue['labels'] + ',' + get_current_week_label
    options['milestone_id'] = get_or_create_milestone['id']
    options['assignee_id'] = @current_user["id"]
    created_issue = Gitlab.create_issue(CONFIG["project_id"], issue['title'], options).to_h
    Gitlab.estimate_time_of_issue(CONFIG["project_id"], created_issue["iid"], issue['time_estimate'])
    ap "Created issue at #{created_issue["web_url"]}"
  end
end


def current_user
  ap @current_user
end

ACTIONS = {
    1 => "log_time",
    2 => "create_issue",
    3 => "current_user",
    4 => "create_recurring_issues"
}

ap "Available Actions"
ap ACTIONS

selected_option = Readline.readline(">", true).to_i
abort("Aborting! Invalid option") unless ACTIONS.keys.include? selected_option
send(ACTIONS[selected_option])