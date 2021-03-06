class CommentsController < ApplicationController
  def create
    if params[:pull_request_id]
      @comment = PullRequest.find(params[:pull_request_id].to_i).comments.build(comment_params)
      comment_save(@comment)
      redirect_to repository_pull_request_path(id: params[:pull_request_id])
    else
      @comment = Issue.find(params[:issue_id].to_i).comments.build(comment_params)
      comment_save(@comment)
      redirect_to repository_issue_path(id: params[:issue_id])
    end
  end

  def update
    comment = Comment.find(params[:id])
    if comment.user.id == current_user.id
      comment.update(comment_params)
      redirect_path
    else
      redirect_path
    end
  end

  def destroy
    comment = Comment.find(params[:id])
    if comment.user.id == current_user.id
      comment.destroy
      redirect_path
    else
      redirect_path
    end
  end

  private
  def comment_params
    params.require(:comment).permit(:content)
  end

  def comment_save(comment)
    comment.user_id = current_user.id
    if comment.save
      flash[:notice] = 'You have created a comment.'
    else
      flash[:notice] = 'something wrong.'
    end
  end

  def redirect_path
    if params[:pull_request_id]
      redirect_to repository_pull_request_path(id: params[:pull_request_id])
    else
      redirect_to repository_issue_path(id: params[:issue_id])
    end
  end
end