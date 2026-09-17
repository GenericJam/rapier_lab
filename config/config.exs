import Config

# rapier_lab-d00: on device, mob_dev's flat OTP bundle doesn't register
# per-dep code paths, so Application.app_dir(:mob_rapier) raises inside
# Rustler's on_load. Point mob_rapier at the host app for the load — the
# priv/ lookup then goes through :rapier_lab's known-good path, which is
# fine because on device it's the static-linked NIF and on host dev the
# .so still lives at deps/mob_rapier/priv/native/lab_physics.so which
# Rustler resolves relative to whatever otp_app we name (both work as long
# as compile_env is stable at build time). Follow-up: MOB-254.
config :mob_rapier, :otp_app, :rapier_lab
