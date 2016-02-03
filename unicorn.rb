user "web", "web"
working_directory "/var/www/vocabincontext"
pid "/var/www/vocabincontext/unicorn.pid"
stderr_path "/var/log/unicorn.log"
stdout_path "/var/log/unicorn.log"
listen "/tmp/unicorn.vocabincontext.sock"
worker_processes 1
timeout 3600
preload_app true
listen 9292
