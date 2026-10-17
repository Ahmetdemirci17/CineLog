module Admin
  class CommunityRepliesController < BaseController
    def destroy
      @post = CommunityPost.find(params[:community_post_id])
      @reply = @post.community_replies.find(params[:id])
      @reply.destroy
      redirect_back fallback_location: admin_community_post_path(@post), notice: "Yanıt silindi."
    end
  end
end
