class LibraryScanJob < ApplicationJob
  queue_as :default

  # Find all files in the library that we might need to look at
  def filenames_on_disk(library)
    # Dir.glob(File.join(library.path, "**", ApplicationJob.file_pattern))
    Dir.glob(File.join(library.path, "**/*")).reject { |filename| File.directory?(filename) }
    # TODO maybe: recursive glob, removing directories is best right?
  end

  # Get a list of all the existing filenames
  def known_filenames(library)
    library.model_files.reload.map do |x|
      File.join(library.path, x.model.path, x.filename)
    end
  end

  # any path that is a subdirectory of an existing model: process as that model
  def model_trim_paths(library, folders)
    matching_models = []
    library.models.map do |x|
      if folders.reject! { |folder| Regexp.new("^" + File.join(library.path, x.path)).match?(folder) }
        matching_models.push(File.join(library.path, x.path))
      end
    end
    logger.debug("xyzzy trimmed")
    logger.debug(matching_models)
    folders.concat(matching_models)
  end

  def clean_up_missing_models(library)
    library.models.each do |m|
      if !File.exist?(File.join(library.path, m.path))
        begin
          m.problems.create(category: :missing)
        rescue
          nil
        end
      else
        m.problems.where(category: :missing).destroy_all
      end
    end
    nil
  end

  def clean_up_missing_model_files(library)
    library.model_files.each do |f|
      if !File.exist?(f.pathname)
        begin
          f.problems.create(category: :missing)
        rescue
          nil
        end
      else
        f.problems.where(category: :missing).destroy_all
      end
    end
    nil
  end

  def filter_out_common_subfolders(folders)
    # TODO maybe: with a recursive scan (and reject directories), these go away
    ignorable_leaf_folders = [
      "files", # Thingiverse download structure
      "images" # Thingiverse download structure
    ]
    matcher = /\/(#{ignorable_leaf_folders.join('|')})$/
    folders.map { |f| f.gsub(matcher, "") }.uniq
  end

  def perform(library)
    if !File.exist?(library.path)
      library.problems.create(category: :missing)
    else
      library.problems.where(category: :missing).destroy_all
    end
    # Remove models with missing path
    clean_up_missing_models(library)
    clean_up_missing_model_files(library)
    # Make a list of changed filenames using set XOR
    changes = (known_filenames(library).to_set ^ filenames_on_disk(library)).to_a
    # Make a list of library-relative folders with changed files
    folders_with_changes = changes.map { |f| File.dirname(f.gsub(library.path, "")) }.uniq
    # TODO:  whack subfolders of other things here.
    folders_with_changes = model_trim_paths(library, folders_with_changes)
    # trim based on library models
    # kill any subdirs (set min depth first?)
    folders_with_changes = filter_out_common_subfolders(folders_with_changes).uniq
    folders_with_changes.delete("/")s
    folders_with_changes.compact_blank!
    # For each folder in the library with a change, find or create a model, then scan it
    logger.debug(folders_with_changes)
    folders_with_changes.each do |path|
      new_model_properties = {
        name: File.basename(path).humanize.tr("+", " ").titleize
      }
      model = library.models.create_with(new_model_properties).find_or_create_by(path: path)
      if model.valid?
        ModelScanJob.perform_later(model)
      else
        Rails.logger.error(model.inspect)
        Rails.logger.error(model.errors.full_messages.inspect)
      end
    end
  end
end
