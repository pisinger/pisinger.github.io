#!/usr/bin/env ruby
#
# Check for changed posts

[:posts, :ms_release_radar, :wiz_release_radar, :ms_tech_blogs].each do |collection|
  Jekyll::Hooks.register collection, :post_init do |doc|

    commit_num = `git rev-list --count HEAD "#{ doc.path }"`

    if commit_num.to_i > 1
      lastmod_date = `git log -1 --pretty="%ad" --date=iso "#{ doc.path }"`
      doc.data['last_modified_at'] = lastmod_date
    end

  end
end
