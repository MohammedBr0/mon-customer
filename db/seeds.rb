# frozen_string_literal: true

# Idempotent: safe to run on every deploy.
VehicleField.seed_defaults!
PlatformSetting.current
