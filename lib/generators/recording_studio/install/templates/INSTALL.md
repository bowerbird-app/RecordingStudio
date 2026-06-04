# RecordingStudio Installed

Next steps:

1. Run `bin/rails db:migrate`.
2. Review `config/initializers/recording_studio.rb` and `config/recording_studio.yml` if you opted into the YAML file.
3. Add `recording_studio_recordable` declarations to each configured recordable model:
	- root types use `root: true`
	- child-only types use `root: false, allowed_parent_types: [...]`
4. Set `Current.actor` and `Current.impersonator`, or pass `actor:` and `impersonator:` explicitly from your app.
5. If your app uses Tailwind, rebuild assets with `bin/rails tailwindcss:build`.
6. The `/recording_studio` mount is not a bundled UI. Start integrating through `RecordingStudio.root_recording_for(...)` and the API docs instead.
