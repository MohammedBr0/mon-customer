# frozen_string_literal: true

module Admin
  # Staff check the driving licences and national IDs people send in.
  class IdentityDocumentsController < BaseController
    before_action :set_document, only: %i[show image approve reject]

    def index
      status = IdentityDocument::STATUSES.include?(params[:status]) ? params[:status] : 'pending'
      @status = status
      @documents = IdentityDocument.without_image.where(status:).includes(:user).order(updated_at: :desc).page(params[:page])
      @pending_count = IdentityDocument.pending.count
    end

    def show; end

    # The picture itself: staff only, never cached by browsers or proxies.
    def image
      response.headers['Cache-Control'] = 'private, no-store'
      audit!('identity_document.view', @document, kind: @document.kind)
      send_data @document.image, type: @document.content_type, disposition: 'inline'
    end

    def approve
      @document.approve!(by: current_user)
      audit!('identity_document.approve', @document, kind: @document.kind, user_id: @document.user_id)
      redirect_to admin_identity_documents_path, flash: { success: t('identity.flash.approved') }
    end

    def reject
      @document.reject!(by: current_user, reason: params[:reason])
      audit!('identity_document.reject', @document, kind: @document.kind, user_id: @document.user_id)
      redirect_to admin_identity_documents_path, flash: { success: t('identity.flash.rejected') }
    end

    private

    def set_document
      @document = IdentityDocument.find(params[:id])
    end
  end
end
