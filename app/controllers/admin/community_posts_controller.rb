module Admin
  class CommunityPostsController < BaseController
    before_action :set_post, only: [:show, :destroy]

    def index
      @posts = CommunityPost.includes(:user, :community_replies).order(created_at: :desc)

      if params[:query].present?
        q = "%#{params[:query].strip.downcase}%"
        @posts = @posts.where("lower(title) LIKE ? OR lower(content) LIKE ?", q, q)
      end

      @posts = @posts.page(params[:page]).per(20) if defined?(Kaminari)
    end

    def show
      @replies = @post.community_replies.includes(:user).order(created_at: :asc)
    end

    def destroy
      title = @post.title
      @post.destroy
      redirect_to admin_community_posts_path, notice: "\"#{title}\" başlıklı gönderi silindi."
    end

    private

    def set_post
      @post = CommunityPost.find(params[:id])
    end
  end
end
