load File.expand_path("../set_rails_env.rake", __FILE__)

module Capistrano
  class FileNotFound < StandardError
  end
end

namespace :deploy do
  desc 'Normalize asset timestamps'
  task :normalize_assets => [:set_rails_env] do
    on release_roles(fetch(:assets_roles)) do
      assets = fetch(:normalize_asset_timestamps)
      if assets
        within release_path do
          execute :find, "#{assets} -exec touch -t #{asset_timestamp} {} ';'; true"
        end
      end
    end
  end

  desc 'Compile assets'
  task :compile_assets => [:set_rails_env] do
    invoke 'deploy:assets:precompile'
    invoke 'deploy:assets:backup_manifest'
  end

  # FIXME: it removes every asset it has just compiled
  desc 'Cleanup expired assets'
  task :cleanup_assets => [:set_rails_env] do
    on release_roles(fetch(:assets_roles)) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "assets:clean"
        end
      end
    end
  end

  desc 'Rollback assets'
  task :rollback_assets => [:set_rails_env] do
    begin
      invoke 'deploy:assets:restore_manifest'
    rescue Capistrano::FileNotFound
      invoke 'deploy:compile_assets'
    end
  end

  after 'deploy:updated', 'deploy:compile_assets'
  # NOTE: we don't want to remove assets we've just compiled
  # after 'deploy:updated', 'deploy:cleanup_assets'
  after 'deploy:updated', 'deploy:normalize_assets'
  after 'deploy:reverted', 'deploy:rollback_assets'

  namespace :assets do
    task :precompile do
      on release_roles(fetch(:assets_roles)) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            execute :rake, "assets:precompile"
          end
        end
      end
    end

    task :backup_manifest do
      on release_roles(fetch(:assets_roles)) do
        within release_path do
          execute :mkdir, '-p', release_path.join('tmp', 'capistrano_assets_backup')
          execute :cp,
            release_path.join('public', fetch(:assets_prefix), 'manifest*'),
            release_path.join('tmp', 'capistrano_assets_backup')
        end
      end
    end

    task :restore_manifest do
      on release_roles(fetch(:assets_roles)) do
        within release_path do
          source = release_path.join('tmp', 'capistrano_assets_backup', 'manifest*')
          target = release_path.join('public', fetch(:assets_prefix))
          manifests = capture(:ls, release_path.join('public', fetch(:assets_prefix), 'manifest*')).split

          execute :cp, source, target
          manifests.each do |manifest|
            info "#{manifest.split('/').last} restored."
          end
        end
      end
    end

  end
end

namespace :load do
  task :defaults do
    set :assets_roles, fetch(:assets_roles, [:web])
    set :assets_prefix, fetch(:assets_prefix, 'assets')
    set :linked_dirs, fetch(:linked_dirs, []).push("public/#{fetch(:assets_prefix)}")
  end
end
