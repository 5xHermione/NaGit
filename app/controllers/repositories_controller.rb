class RepositoriesController < ApplicationController
  before_action :set_repository, only: [:show, :edit, :update, :destroy]

  def index
    if current_user
      @repositories = current_user.repositories.order("id DESC").includes(:user)
    else
      redirect_to new_user_session_path
    end
  end

  def show

    user_name = @repository.user.name
    repo_title = @repository.title

    #synchronize git working repo 
    Dir.chdir("/tmp/gitServer/#{user_name}/#{repo_title}")
    `git pull`

    #set base path and repo path
    @base_path = "/tmp/gitServer"
    @current_repo_path = "./#{user_name}/#{repo_title}"
    Dir.chdir(@base_path)
    Dir.chdir(@current_repo_path)

    #set directory path
    @path = request.original_fullpath
    if @path.match(/^\/repositories\/.+\/worktree\/master\/(.+)/)
      @path = @path.match(/^\/repositories\/.+\/worktree\/master\/(.+)/)[1]
    else
      @path = "."
    end 

    @files = []
    @dirs = []

    @is_file = File.file?(@path)

    if @is_file
      @files = File.readlines(@path)
    else
      Dir.entries(@path).each do |file|
        if [".", "..", ".git"].include?"#{file}"
        #rule out ".", "..", ".git"
        elsif File.file?(@path+"/"+file)
          @files << "#{@path}/#{file}"
        else
          @dirs << "#{@path}/#{file}"
        end
      end
    end


  end

  def new
    @repository = Repository.new
  end

  def edit
  end

  def create
    @repository = current_user.repositories.new(repository_params)
    @repository.errors.add(:is_public, "must select one") if params[:is_public].nil?


    if @repository.errors.any?
      render :new
    else
      if @repository.save
        title = @repository.title
        bare_repo_dir = "#{title}.git"

        full_dir = "/tmp/gitServer/#{current_user.name}/#{bare_repo_dir}"
        working_dir = "/tmp/gitServer/#{current_user.name}/#{title}"

        #新增一個空的資料夾
        `mkdir -p #{full_dir}`
        #在剛剛新增的空資料夾中建立一個 bare repo
        #bare repo 可以被push clone
        #bare repo 中是沒有檔案的
        `git --bare init #{full_dir}`
        #要讓網頁可以使用檔案、可以 commit 、需要的是 working repo （也就是我們平常 git init 之後的創造出來的 git 目錄）
        # 從 bare repo 中 clone 出一個 working repo，讓我們有檔案可以處理
        `git clone #{full_dir}  #{working_dir}`
        redirect_to repositories_path, notice: 'You have created a repository.' 
      else
        render :new
      end
    end
  end

  def update
    if @repository.update(repository_params)
      redirect_to repositories_path, notice: 'This repository has updated.'
    else
      render :edit
    end
  end

  def destroy
    @repository.destroy
    redirect_to repositories_path, notice: 'This repository is deleted！'
  end

  private
    def set_repository
      @repository = Repository.friendly.find(params[:id])
      session[:repository_id] = @repository.id
    end

    def repository_params
      params.require(:repository).permit(:title, :description, :user_id, :is_public, :slug)
    end
end
