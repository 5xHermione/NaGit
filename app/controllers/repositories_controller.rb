class RepositoriesController < ApplicationController
  before_action :set_repository, only: [:show, :edit, :update, :destroy, :branch_delete, :branches]
  before_action :set_request_format, only: [:show]
  before_action :set_git_remote_path, only: [:commits, :branches, :contributors, :branch_delete, :edit, :commit_diff]
  before_action :set_repo_file_path, only: [:branch_delete]

  def index
    return redirect_to new_user_session_path if current_user.blank?

    @user = find_user
    @repositories = repositories_order
    @repositories = @repositories.where(is_public: true) if current_user != find_user
    @repositories = @repositories.where('title LIKE ?', "%#{params[:search]}%") if params[:search].present?

    respond_to do |format|
      format.html { render :index }
    end
  end

  def show
    set_repo_file_path

    # synchronize git working repo 
    logger.info `git -C #{@base_path}#{@current_repo_path} fetch`
    logger.info `git -C #{@base_path}#{@current_repo_path} reset --hard origin/master`
    @contributors = []

    if Dir.entries("#{@base_path}#{@current_repo_path}") == [".", "..", ".git"]
      @is_new_repo = true 
      @branches = []
      @commits = 0
      @pull_request_able = []
    else
      @is_new_repo = false
      git_file = Git.open("#{@base_path}#{@current_repo_path}")
      logger.info `git -C #{@base_path}#{@current_repo_path} fetch`
      logger.info `git -C #{@base_path}#{@current_repo_path} reset --hard origin/#{git_file.current_branch}`
      @default_branch = @repository.default_branch
      @current_branch = git_file.current_branch
      @branches = git_file.branches.remote
      @commits = git_file.log(99999).count
      @contributors = git_file.log(99999).map{|commit| commit.committer.name}.uniq.select{|con| con != "GitHub"}
      @pull_request_able = @branches.map{|b| b.name }.select{|b| `git -C #{@base_path}#{@current_repo_path}.git diff #{@default_branch}...#{b}`.present? && current_repository.pull_requests.find_by(compare_branch: b).nil?}

      if request.fullpath.split("/").length == 4 # 專案根目錄的路徑 split 後只會有四個字串，超過四個字的都是比較下層的路徑
        @lines = []
        @readme = File.exist?("#{@base_path}#{@current_repo_path}/README.md")
        if @readme
          File.readlines("#{@base_path}#{@current_repo_path}/README.md").each do |line|
            @lines << line
          end
        end
        @lines = @lines.join("\n")
      end

      repo = Rugged::Repository.new("#{@base_path}#{@current_repo_path}")
      project = Linguist::Repository.new(repo, repo.head.target_id)
      @languages = project.languages.map{|lang| [lang[0], (lang[1].to_f / project.size * 100).round(2)]}
    end

    # get folder path from url
    path = request.original_fullpath
    if path.match(/\/repositories\/.+\/worktree\/master\/(.+)/)
      path = "#{@base_path}#{@current_repo_path}"+"/"+path.match(/\/repositories\/.+\/worktree\/master\/(.+)/)[1]
    else
      path = "#{@base_path}#{@current_repo_path}/."
    end

    files = []
    dirs = []

    is_file = File.file?(path)
    
    if @is_new_repo && current_user == find_user
      render :how_to_push
    elsif @is_new_repo && current_user != find_user
      render :empty_repo
    elsif is_file
      file_data = File.read(path)
      render :file , locals: {file_data: file_data}
    else
      Dir.entries(path).each do |file|

        last_commit = `git -C #{@base_path}#{@current_repo_path} log -1 --pretty=format:"%s___FengChenShowGit___%cr" #{path}/#{file}`
        commit_array = last_commit.split("___FengChenShowGit___")
        last_commit_message = commit_array[0]
        last_commit_time = commit_array[1]

        if [".", "..", ".git"].include?"#{file}"
        #rule out ".", "..", ".git"
        elsif File.file?(path+"/"+file)
          files << ["#{path.match(/^#{@base_path}#{@current_repo_path}\/(.+)/)[1]}/#{file}", last_commit_message, last_commit_time]
        else
          dirs << ["#{path.match(/^#{@base_path}#{@current_repo_path}\/(.+)/)[1]}/#{file}", last_commit_message, last_commit_time]
        end
      end
      render :dir, locals: {dirs: dirs, files: files, repository: @repository}
    end
  end

  def new
    @repository = Repository.new
  end

  def edit
    redirect_to repository_path if current_user != find_user
    @branches = @git_file.branches.remote
  end

  def create
    @repository = current_user.repositories.new(repository_params)
    @repository.errors.add(:is_public, "must select one") if params[:is_public].nil?

    if @repository.errors.any?
      render :new
    else
      @repository.is_public = params[:is_public]
      if @repository.save
        session[:repository_title] = @repository.title
        set_repo_file_path
        @repository.path = "#{@base_path}#{@current_repo_path}"

        full_dir = "#{@base_path}#{@current_repo_path}.git"
        working_dir = "#{@base_path}#{@current_repo_path}"

        # 新增一個空的資料夾
        `mkdir -p #{full_dir}`
        # 在剛剛新增的空資料夾中建立一個 bare repo
        #bare repo 可以被push clone
        #bare repo 中是沒有檔案的
        `git --bare init #{full_dir}`
        # 要讓網頁可以使用檔案、可以 commit 、需要的是 working repo （也就是我們平常 git init 之後的創造出來的 git 目錄）
        # 從 bare repo 中 clone 出一個 working repo，讓我們有檔案可以處理
        `git clone #{full_dir}  #{working_dir}`
        redirect_to repository_path(user_name: find_user.name, id: @repository.title), notice: 'You have created a repository.' 
      else
        render :new
      end
    end
  end

  def update
    old_repo_name = current_repository.title

    if @repository.update(repository_params)
      if params[:repository][:is_public] == "Public"
        @repository.is_public = true
      else
        @repository.is_public = false
      end
      @repository.save
      #update repo name in gitServer
      if old_repo_name != @repository.title
        set_repo_file_path
        logger.info `mv #{@base_path}/#{find_user.name}/#{old_repo_name}.git #{@base_path}/#{find_user.name}/#{@repository.title}.git`
        logger.info `mv #{@base_path}/#{find_user.name}/#{old_repo_name} #{@base_path}/#{find_user.name}/#{@repository.title}`
        logger.info `git -C #{@base_path}/#{find_user.name}/#{@repository.title} remote set-url origin #{ENV["GIT_PUSH_INSTRUCT"]}/#{find_user.name}/#{@repository.title}.git`
      end
      redirect_to repository_path(user_name: find_user.name, id: @repository.title), notice: 'This repository has updated.'
    else
      render :edit
    end
  end

  def destroy
    #destroy whole repo folder on git server
    set_repo_file_path
    `rm -rf #{@base_path}#{@current_repo_path}.git`
    `rm -rf #{@base_path}#{@current_repo_path}`

    @repository.destroy
    redirect_to repositories_path, notice: 'This repository is deleted！'
  end

  def checkout
    set_repo_file_path
    `git -C #{@base_path}#{@current_repo_path} checkout #{params[:branch]}`
    redirect_to repository_path(user_name: find_user.name, id: current_repository.title )
  end

  def commits
    @commits = @git_file.log(99999)
    @branches = @git_file.branches.remote.map{|b| b.name}
    @contributors = @git_file.log(99999).map{|c| c.committer.name}.uniq.select{|n|n != "Github"}.count
  end

  def commit_diff
    @commit_diff_files = diff_files_in_commit(params[:sha])

    @branches = @git_file.branches.remote
    @commits = @git_file.log(99999).count
    @contributors = @git_file.log(99999).map{|c| c.committer.name}.uniq.select{|n|n != "Github"}.count
  end

  def branches
    @branches = @git_file.branches.remote
    @commits = @git_file.log(99999).count
    @contributors = @git_file.log(99999).map{|c| c.committer.name}.uniq.select{|n|n != "Github"}.count
  end

  def branch_delete
    if params[:branch] != @repository.default_branch
      `git -C #{@base_path}#{@current_repo_path} branch -D #{params[:branch]}`
      `git -C #{@base_path}#{@current_repo_path}.git branch -D #{params[:branch]}`
      `git -C #{@base_path}#{@current_repo_path} fetch --all -p`
      flash[:notice] = "Branch deleted successfully!"
    else
      flash[:notice] = "You can't delete default branch!"
    end
    redirect_to repository_path(user_name: find_user.name, id: current_repository.title)
  end

  private
  def set_repository
    @repository = find_user.repositories.friendly.find(params[:id])
    session[:repository_title] = @repository.title
  end

  def repository_params
    params.require(:repository).permit(:title, :description, :is_public, :default_branch)
  end

  def set_request_format
    request.format = :html
  end

  def diff_files_in_commit(commit)
    diff_commit = DiffPullRequest.new(
      "#{@base_path}#{@current_repo_path}",
      sha: commit
    )
    diff_commit.diff_in_files
  end
end

