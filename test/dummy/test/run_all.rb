# frozen_string_literal: true

Dir[File.expand_path("**/*_test.rb", __dir__)].sort.each do |path|
  next if path.end_with?("run_all.rb")

  require path
end
