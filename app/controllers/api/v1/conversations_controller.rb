# frozen_string_literal: true

module Api
  module V1
    class ConversationsController < BaseController
      def index
        records, meta = paginate(current_user.conversations.includes(:sender, :receiver, :conversable).order(updated_at: :desc))
        render json: { conversations: records.map { |conversation| serializer.conversation(conversation, viewer: current_user) }, meta:,
                       unread: current_user.unread_conversations_count }
      end

      def show
        conversation = current_user.conversations.includes(messages: :sender).find(params[:id])
        conversation.mark_as_read!(current_user)
        render json: { conversation: serializer.conversation(conversation, viewer: current_user, messages: true) }
      end

      # Starts a conversation with a trip's driver, or adds to the existing one.
      def create
        itinerary = Itinerary.friendly.find(params.require(:itinerary_id))
        return render_error('forbidden', I18n.t('flash.errors.not_allowed'), :forbidden) if itinerary.user == current_user

        conversation = itinerary.conversations.find_or_initialize_by(sender: current_user, receiver: itinerary.user)
        conversation.messages.build(body: params.require(:body), sender: current_user)
        save_and_render(conversation, status: :created)
      end

      def message
        conversation = current_user.conversations.find(params[:id])
        conversation.messages.build(body: params.require(:body), sender: current_user)
        save_and_render(conversation)
      end

      private

      def save_and_render(conversation, status: :ok)
        if conversation.save
          render json: { conversation: serializer.conversation(conversation.reload, viewer: current_user, messages: true) }, status:
        else
          render_invalid conversation
        end
      end
    end
  end
end
