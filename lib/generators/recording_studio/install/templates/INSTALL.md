# RecordingStudio Installed

Next steps:

1. Run `bin/rails db:migrate`.
2. Review `config/initializers/recording_studio.rb`.
3. Add `recording_studio_recordable` declarations to each configured recordable model:
	- root types use `root: true`
	- child-only types use `root: false, allowed_parent_types: [...]`
4. If your app uses Tailwind, rebuild assets with `bin/rails tailwindcss:build`.
