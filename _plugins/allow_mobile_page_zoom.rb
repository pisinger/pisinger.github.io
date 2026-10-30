# frozen_string_literal: true

# Chirpy 7.6.0 marks its viewport as user-scalable=no, which prevents native
# two-finger browser zoom on mobile. Keep the theme's responsive viewport
# settings, but remove that restriction from every generated page/document.
require 'jekyll'

Jekyll::Hooks.register :site, :post_render do |site|
  pages = site.pages + site.collections.values.flat_map(&:docs)

  pages.each do |page|
    next unless page.output

    page.output = page.output.gsub(/width=device-width,\s*user-scalable=no\s*/, 'width=device-width, ')
  end
end
