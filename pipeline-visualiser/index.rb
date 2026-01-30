require 'activesupport-duration-human_string'
require 'json'
require 'ostruct'
require 'sinatra'
require 'yaml'

require_relative './background_pipeline_status_updates'

require_relative 'lib/aws-sdk-factory/live'
require_relative 'lib/aws-sdk-factory/sso'

require_relative 'lib/views/all_pipelines'
require_relative 'lib/views/group'

set :public_folder, 'public'
set :bind, '0.0.0.0'

helpers do
  def slugify(str)
    str.downcase
       .gsub(%r{[ _:/]}, '-')
  end

  def active_page_css_class?(path)
    request.path_info == path ? 'govuk-header__navigation-item--active' : ''
  end
end

is_sso_mode = ENV.fetch('PIPELINE_VISUALISER_SSO_MODE', 'false') == 'true'

config = YAML.safe_load_file('./config.yml')

aws_clients = []
if is_sso_mode
  config['roles'].each do |role|
    if role['sso_config']
      aws_clients << {
        'client' => SSOAWSSDKFactory.new_code_pipeline(role['sso_config'])
      }
    end
  end
else
  # Use ECS task role with cross-account role assumption
  config['ecs_roles'].each do |role_config|
    aws_clients << {
      'client' => LiveAWSSDKFactory.new_code_pipeline(role_config['role_arn']),
      'gds_cli_role' => role_config['role_arn']
    }
  end
end

pipelines_map = start_background_pipeline_status_updater(aws_clients)

get '/' do
  groups = []
  config['groups'].each_key do |k|
    group_elements = config['groups'][k]
    group_pipelines = group_elements
                      .map { |name| pipelines_map.fetch(name, nil) }
                      .reject(&:nil?)
    group = PipelineGroup.new(k, group_pipelines)
    groups << group
  end

  view = AllPipelinesView.new(groups)
  erb :index, locals: { view: }
end

get '/deploying-changes' do
  erb :deploying_changes
end

get '/group/:group_slug' do
  all_groups = config['groups'].to_a
  group = all_groups.find { |grp| params['group_slug'] == slugify(grp[0]) }
  pass if group.nil?

  pipeline_names = group[1]
  pipelines = pipeline_names
              .map { |name| pipelines_map.fetch(name, nil) }
              .reject(&:nil?)

  erb :group, locals: {
    view: Group.new(group[0], pipelines),
    breadcrumbs: {
      'Home' => '/'
    }
  }
end

get '/group/:group_slug/pipeline/:pipeline_slug' do
  all_groups = config['groups'].to_a
  group_slugs_to_names = config['groups'].keys.map { |name| [slugify(name), name] }.to_h
  group = all_groups.find { |grp| params['group_slug'] == slugify(grp[0]) }
  pass if group.nil?

  pipeline_slugs_to_names = group[1].map { |name| [slugify(name), name] }.to_h
  pass unless pipeline_slugs_to_names.keys.include? params['pipeline_slug']

  group_name = group_slugs_to_names[params['group_slug']]
  pipeline_name = pipeline_slugs_to_names[params['pipeline_slug']]
  pipeline = pipelines_map[pipeline_name]

  erb :pipeline, locals: {
    pipeline:,
    breadcrumbs: {
      'Home' => '/',
      group_name => "/group/#{params['group_slug']}"
    }
  }
end

not_found do
  erb :not_found
end
