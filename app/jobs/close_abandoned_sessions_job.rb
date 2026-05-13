class CloseAbandonedSessionsJob < ApplicationJob
  queue_as :default

  # Cualquier sesión activa de más de esta antigüedad se considera abandonada
  # (server crash, browser cerrado, etc.). Para timeout de inactividad real,
  # habilita :timeoutable en el modelo User.
  MAX_SESSION_AGE = 24.hours

  def perform
    UserSession.active
               .where('started_at < ?', MAX_SESSION_AGE.ago)
               .find_each do |session|
      session.update!(
        ended_at: Time.current,
        duration_seconds: nil,
        sign_out_reason: 'orphaned'
      )
    end
  end
end
