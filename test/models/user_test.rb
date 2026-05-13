require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @user = create_test_user
  end

  test "user has association with processed files" do
    assert_respond_to @user, :processed_files
    assert_equal [], @user.processed_files.to_a
  end

  test "user can have multiple processed files" do
    file1 = ProcessedFile.create!(
      original_filename: "file1.xlsx",
      status: "completed",
      user: @user
    )
    
    file2 = ProcessedFile.create!(
      original_filename: "file2.xlsx", 
      status: "pending",
      user: @user
    )

    assert_equal 2, @user.processed_files.count
    assert_includes @user.processed_files, file1
    assert_includes @user.processed_files, file2
  end

  test "destroying user destroys associated files" do
    ProcessedFile.create!(
      original_filename: "file1.xlsx",
      status: "completed", 
      user: @user
    )

    assert_equal 1, ProcessedFile.count
    @user.destroy
    assert_equal 0, ProcessedFile.count
  end

  test "total_files_uploaded returns correct count" do
    assert_equal 0, @user.total_files_uploaded

    ProcessedFile.create!(original_filename: "file1.xlsx", status: "pending", user: @user)
    ProcessedFile.create!(original_filename: "file2.xlsx", status: "completed", user: @user)
    ProcessedFile.create!(original_filename: "file3.xlsx", status: "failed", user: @user)

    assert_equal 3, @user.total_files_uploaded
  end

  test "total_files_processed returns only completed files" do
    assert_equal 0, @user.total_files_processed

    ProcessedFile.create!(original_filename: "file1.xlsx", status: "pending", user: @user)
    ProcessedFile.create!(original_filename: "file2.xlsx", status: "completed", user: @user)
    ProcessedFile.create!(original_filename: "file3.xlsx", status: "completed", user: @user)
    ProcessedFile.create!(original_filename: "file4.xlsx", status: "failed", user: @user)

    assert_equal 2, @user.total_files_processed
  end

  test "last_activity returns latest between sign in and file activity" do
    # Case 1: No activity at all
    assert_nil @user.last_activity

    # Case 2: Only sign in activity
    @user.update!(last_sign_in_at: 2.days.ago)
    assert_equal 2.days.ago.to_date, @user.last_activity.to_date

    # Case 3: File activity is more recent
    file = ProcessedFile.create!(
      original_filename: "file1.xlsx",
      status: "completed",
      user: @user
    )
    file.update!(updated_at: 1.day.ago)

    assert_equal 1.day.ago.to_date, @user.last_activity.to_date

    # Case 4: Sign in is more recent
    @user.update!(last_sign_in_at: 1.hour.ago)
    assert_equal 1.hour.ago.to_date, @user.last_activity.to_date
  end

  test "current_session returns the latest active user_session" do
    assert_nil @user.current_session

    older = @user.user_sessions.create!(started_at: 2.hours.ago)
    newer = @user.user_sessions.create!(started_at: 10.minutes.ago)
    @user.user_sessions.create!(
      started_at: 1.hour.ago,
      ended_at: 30.minutes.ago,
      duration_seconds: 1800,
      sign_out_reason: 'manual'
    )

    assert_equal newer, @user.current_session
    assert_not_equal older, @user.current_session
  end

  test "average_session_duration averages only finished sessions" do
    assert_nil @user.average_session_duration

    @user.user_sessions.create!(
      started_at: 2.hours.ago, ended_at: 1.hour.ago,
      duration_seconds: 3600, sign_out_reason: 'manual'
    )
    @user.user_sessions.create!(
      started_at: 4.hours.ago, ended_at: 3.hours.ago,
      duration_seconds: 1800, sign_out_reason: 'manual'
    )
    @user.user_sessions.create!(started_at: 5.minutes.ago)

    assert_in_delta 2700.0, @user.average_session_duration.to_f, 0.01
  end

  test "total_time_logged_in sums duration_seconds of finished sessions" do
    assert_equal 0, @user.total_time_logged_in

    @user.user_sessions.create!(
      started_at: 2.hours.ago, ended_at: 1.hour.ago,
      duration_seconds: 3600, sign_out_reason: 'manual'
    )
    @user.user_sessions.create!(
      started_at: 4.hours.ago, ended_at: 3.hours.ago,
      duration_seconds: 1800, sign_out_reason: 'manual'
    )
    @user.user_sessions.create!(started_at: 5.minutes.ago)

    assert_equal 5400, @user.total_time_logged_in
  end

  test "devise trackable fields are present" do
    assert_respond_to @user, :sign_in_count
    assert_respond_to @user, :current_sign_in_at
    assert_respond_to @user, :last_sign_in_at
    assert_respond_to @user, :current_sign_in_ip
    assert_respond_to @user, :last_sign_in_ip

    # Test default values
    assert_equal 0, @user.sign_in_count
  end

  test "trackable fields update correctly" do
    @user.update!(
      sign_in_count: 5,
      current_sign_in_at: Time.current,
      last_sign_in_at: 1.day.ago,
      current_sign_in_ip: "192.168.1.1",
      last_sign_in_ip: "192.168.1.2"
    )

    @user.reload
    assert_equal 5, @user.sign_in_count
    assert_not_nil @user.current_sign_in_at
    assert_not_nil @user.last_sign_in_at
    assert_equal "192.168.1.1", @user.current_sign_in_ip
    assert_equal "192.168.1.2", @user.last_sign_in_ip
  end
end
