# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "controllers", to: "controllers/index.js"
pin "controllers/generation_stream_controller", to: "controllers/generation_stream_controller.js"
pin "controllers/theme_controller", to: "controllers/theme_controller.js"
