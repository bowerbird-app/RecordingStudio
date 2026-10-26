# frozen_string_literal: true

namespace :flat_pack do
  desc "Print the FlatPack components path for Tailwind @source"
  task tailwind_source: :environment do
    puts FlatPack::Engine.root.join("app/components")
  end
end
