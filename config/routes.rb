# frozen_string_literal: true

RecordingStudio::Engine.routes.draw do
  root "home#index", as: :recording_studio_root
end
