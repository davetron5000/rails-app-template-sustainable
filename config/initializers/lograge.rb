Rails.application.configure do
  if !Rails.env.development? ||
      ENV["LOGRAGE_IN_DEVELOPMENT"] == "true"
    config.lograge.enabled = true
  else
    config.lograge.enabled = false
  end
end

