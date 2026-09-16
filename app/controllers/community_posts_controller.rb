class CommunityPostsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_community_post, only: [:show, :destroy]

  def index
    @posts = CommunityPost.includes(:user, :community_replies).recent
  end

  def show
    @reply = CommunityReply.new
    @replies = @community_post.community_replies.includes(:user).chronological

    if @community_post.tmdb_id.present?
      if @community_post.media_type == "tv"
        @attached_media = TmdbService.new.tv_details(@community_post.tmdb_id)
      else
        @attached_media = TmdbService.new.movie_details(@community_post.tmdb_id)
      end
    end
  end

  def new
    @post = current_user.community_posts.new(
      tmdb_id: params[:tmdb_id],
      media_type: params[:media_type]
    )
    @movie_title = params[:movie_title]
  end

  def create
    @post = current_user.community_posts.new(post_params)

    if @post.save
      redirect_to community_post_path(@post), notice: "Konunuz başarıyla paylaşıldı!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    if @post.user == current_user
      @post.destroy
      redirect_to community_posts_path, notice: "Konu silindi."
    else
      redirect_to community_posts_path, alert: "Bu işlem için yetkiniz yok."
    end
  end

  private

  def set_community_post
    @community_post = CommunityPost.find(params[:id])
  end

  def post_params
    params.require(:community_post).permit(:title, :content, :tmdb_id, :media_type)
  end
end
