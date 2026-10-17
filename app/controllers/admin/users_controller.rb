module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :toggle_admin, :destroy]

    def index
      @users = User.order(created_at: :desc)

      if params[:query].present?
        q = "%#{params[:query].strip.downcase}%"
        @users = @users.where("lower(username) LIKE ? OR lower(email) LIKE ?", q, q)
      end

      if params[:role] == "admin"
        @users = @users.where(admin: true)
      elsif params[:role] == "user"
        @users = @users.where(admin: false)
      end

      @users = @users.page(params[:page]).per(20) if defined?(Kaminari)
    end

    def show
      @watchlists = @user.watchlists.order(created_at: :desc).limit(20)
      @posts = @user.community_posts.order(created_at: :desc).limit(10)
    end

    def toggle_admin
      if @user == current_user
        redirect_to admin_user_path(@user), alert: "Kendi yöneticilik yetkinizi değiştiremezsiniz."
        return
      end

      @user.update(admin: !@user.admin?)
      status_text = @user.admin? ? "Yönetici yapıldı." : "Yöneticilik yetkisi kaldırıldı."
      redirect_back fallback_location: admin_users_path, notice: "#{@user.username} kullanıcısı #{status_text}"
    end

    def destroy
      if @user == current_user
        redirect_to admin_users_path, alert: "Kendi hesabınızı silemezsiniz."
        return
      end

      username = @user.username
      @user.destroy
      redirect_to admin_users_path, notice: "#{username} kullanıcısı ve ilişkili tüm verileri silindi."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end
  end
end
