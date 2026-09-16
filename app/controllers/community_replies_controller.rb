class CommunityRepliesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_community_post

  def create
    @reply = @community_post.community_replies.new(reply_params)
    @reply.user = current_user

    if @reply.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to community_post_path(@community_post), notice: "Yanıtınız gönderildi." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("reply_errors", partial: "shared/error", locals: { message: @reply.errors.full_messages.join(", ") }) }
        format.html { redirect_to community_post_path(@community_post), alert: @reply.errors.full_messages.join(", ") }
      end
    end
  end

  def destroy
    @reply = @community_post.community_replies.find(params[:id])
    if @reply.user == current_user
      @reply.destroy
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to community_post_path(@community_post), notice: "Yanıt silindi." }
      end
    else
      redirect_to community_post_path(@community_post), alert: "Yetkiniz yok."
    end
  end

  private

  def set_community_post
    @community_post = CommunityPost.find(params[:community_post_id])
  end

  def reply_params
    params.require(:community_reply).permit(:content)
  end
end
