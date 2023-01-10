class LibrariesController < ApplicationController
  before_action :get_library, except: [:index, :new, :create]

  def index
    if Library.count === 0
      redirect_to new_library_path
    else
      redirect_to Library.first
    end
  end

  def show
    @models =
      if current_user.pagination_settings["models"]
        page = params[:page] || 1
        @library.models.includes(:tags, :preview_file, :creator).page(page).per(current_user.pagination_settings["per_page"])
      else
        @library.models.includes(:tags, :preview_file, :creator)
      end

    # Ordering
    @models = case session["order"]
    when "recent"
      @models.order(created_at: :desc)
    else
      @models.order(name: :asc)
    end

    @tags = @library.all_tags.select { |x| x.taggings_count > 1 }

    # Filter by tag?
    if params[:tag]
      @tag = ActsAsTaggableOn::Tag.find_by(name: params[:tag])
      @models = @models.tagged_with(@tag) if @tag
    end

    # Filter by collection?
    if params[:collection]
      @collection = ActsAsTaggableOn::Tag.for_context(:collections).find_by(name: params[:collection])
      @models = @models.tagged_with(@collection, context: :collection) if @collection
    end
  end

  def new
    @library = Library.new
    @title = "New Library"
  end

  def create
    @library = Library.create(library_params)
    if @library.valid?
      LibraryScanJob.perform_later(@library)
      redirect_to @library
    else
      render :new
    end
  end

  def update
    LibraryScanJob.perform_later(@library)
    redirect_to @library
  end

  def destroy
    @library.destroy
    redirect_to libraries_path
  end

  private

  def library_params
    params.require(:library).permit(:path)
  end

  def get_library
    @library = Library.find(params[:id])
    @title = @library.name
  end
end
