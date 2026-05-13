# Engancha al ciclo de autenticación de Warden (sobre el que corre Devise) para
# crear un UserSession en cada login y cerrarlo en cada logout. Permite trackear
# duraciones reales de sesión, no solo el último login.
#
# - `after_set_user` con `event: :authentication` solo dispara en login real,
#   no en cada request (el evento `:fetch` es ese, lo excluimos).
# - Si el server se cae con sesiones abiertas, al re-loggear el usuario se
#   marcan las sesiones previas como 'orphaned'. Como respaldo adicional,
#   CloseAbandonedSessionsJob limpia sesiones muy antiguas.
# - Para timeout de inactividad real, considera habilitar `:timeoutable` en User.

Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
  next unless user.is_a?(User)
  next unless opts[:event] == :authentication

  begin
    user.user_sessions.active.update_all(
      ended_at: Time.current,
      duration_seconds: nil,
      sign_out_reason: 'orphaned',
      updated_at: Time.current
    )

    new_session = user.user_sessions.create!(
      started_at: Time.current,
      ip_address: auth.request.remote_ip,
      user_agent: auth.request.user_agent
    )

    scope = opts[:scope] || :user
    # String key: la session se serializa a la cookie y los símbolos se pierden.
    auth.session(scope)['session_record_id'] = new_session.id
  rescue StandardError => e
    Rails.logger.error "[SessionTracking] Error creating session record: #{e.message}"
  end
end

Warden::Manager.before_logout do |user, auth, opts|
  next unless user.is_a?(User)

  begin
    scope = opts[:scope] || :user
    scope_session = auth.session(scope)
    session_id = scope_session.is_a?(Hash) ? (scope_session['session_record_id'] || scope_session[:session_record_id]) : nil
    next unless session_id

    UserSession.find_by(id: session_id)&.close!(reason: 'manual')
  rescue StandardError => e
    Rails.logger.error "[SessionTracking] Error closing session record: #{e.message}"
  end
end
