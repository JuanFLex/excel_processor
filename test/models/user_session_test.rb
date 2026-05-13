require 'test_helper'

class UserSessionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "session_test_#{SecureRandom.hex(4)}@example.com",
      password: 'Password1!',
      password_confirmation: 'Password1!'
    )
  end

  test 'active scope returns only sessions without ended_at' do
    open_s   = @user.user_sessions.create!(started_at: 1.hour.ago)
    closed_s = @user.user_sessions.create!(
      started_at: 2.hours.ago,
      ended_at: 1.hour.ago,
      duration_seconds: 3600,
      sign_out_reason: 'manual'
    )

    assert_includes UserSession.active, open_s
    assert_not_includes UserSession.active, closed_s
  end

  test 'finished scope returns only sessions with ended_at' do
    open_s   = @user.user_sessions.create!(started_at: 1.hour.ago)
    closed_s = @user.user_sessions.create!(
      started_at: 2.hours.ago,
      ended_at: 1.hour.ago,
      duration_seconds: 3600,
      sign_out_reason: 'manual'
    )

    assert_includes UserSession.finished, closed_s
    assert_not_includes UserSession.finished, open_s
  end

  test 'close! sets ended_at, duration_seconds, and sign_out_reason' do
    started = 30.minutes.ago
    closing = Time.current
    s = @user.user_sessions.create!(started_at: started)

    s.close!(reason: 'manual', at: closing)

    assert_not_nil s.ended_at
    assert_in_delta (closing - started).to_i, s.duration_seconds, 1
    assert_equal 'manual', s.sign_out_reason
  end

  test 'close! is idempotent' do
    s = @user.user_sessions.create!(started_at: 1.hour.ago)
    s.close!(reason: 'manual')
    original_ended_at = s.ended_at
    original_duration = s.duration_seconds

    travel 1.hour do
      s.close!(reason: 'manual')
    end

    s.reload
    assert_equal original_ended_at.to_i, s.ended_at.to_i
    assert_equal original_duration, s.duration_seconds
  end

  test 'close! never produces negative duration when at is before started_at' do
    s = @user.user_sessions.create!(started_at: Time.current)
    s.close!(reason: 'manual', at: 1.hour.ago)

    assert_equal 0, s.duration_seconds
  end

  test '#duration on active session returns elapsed time' do
    s = @user.user_sessions.create!(started_at: 10.minutes.ago)
    assert s.duration >= 10 * 60 - 5
    assert s.duration < 11 * 60
  end

  test '#duration on closed session returns duration_seconds' do
    s = @user.user_sessions.create!(
      started_at: 1.hour.ago,
      ended_at: 30.minutes.ago,
      duration_seconds: 1800,
      sign_out_reason: 'manual'
    )
    assert_equal 1800, s.duration
  end

  test 'sign_out_reason validation rejects invalid values' do
    s = @user.user_sessions.build(started_at: Time.current, sign_out_reason: 'invalid')
    assert_not s.valid?
    assert s.errors[:sign_out_reason].any?
  end

  test 'sign_out_reason allows nil for active sessions' do
    s = @user.user_sessions.build(started_at: Time.current)
    assert s.valid?
  end
end
