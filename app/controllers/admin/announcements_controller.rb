# frozen_string_literal: true

module Admin
  # Super admins write a message that lands in people's notifications (and on their phone through the app).
  class AnnouncementsController < SuperController
    MAX_TITLE = 80
    MAX_BODY = 500

    def index
      @recent = recent
    end

    def create
      title = params[:title].to_s.strip
      body = params[:body].to_s.strip
      audience = Notification::AUDIENCES.include?(params[:audience]) ? params[:audience] : 'everyone'
      if title.blank? || body.blank? || title.length > MAX_TITLE || body.length > MAX_BODY
        @recent = recent
        flash.now[:error] = t('announce.invalid', title: MAX_TITLE, body: MAX_BODY)
        return render :index, status: :unprocessable_entity
      end

      count = Notification.announce!(title:, body:, audience:)
      audit!('announcement.send', nil, title:, audience:, recipients: count)
      redirect_to admin_announcements_path, flash: { success: t('announce.sent', count:) }
    end

    private

    # The audit log is the record of what was sent, to whom, and by which admin.
    def recent
      AuditLog.where(action: 'announcement.send').includes(:actor).order(created_at: :desc).limit(10)
    end
  end
end
