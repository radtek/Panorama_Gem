# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'

# Add additional assets to the asset load path
# Rails.application.config.assets.paths << Emoji.images_path

#puts "################### #{Rails.application.config.assets.paths}"

# Precompile additional assets.
# application.js, application.scss, and all non-JS/CSS in app/assets folder are already added.
# Rails.application.config.assets.precompile += %w( search.js )

Rails.application.config.assets.precompile += %w( *.ico *.gif *.png *.jpg )

#Rails.application.config.assets.precompile += %w( favicon.ico favicon_32x32.png favicon_64x64.png )
