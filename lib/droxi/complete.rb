# Module containing tab-completion logic and methods.
module Complete
  # Return an +Array+ of potential command name tab-completions for a +String+.
  def self.command(string, names)
    names.select { |n| n.start_with?(string) }.map { |n| n + ' ' }
  end

  # Return the directory in which to search for potential local tab-completions
  # for a +String+. Defaults to working directory in case of bogus input.
  def self.local_search_path(string)
    File.expand_path(strip_filename(string))
  rescue ArgumentError
    Dir.pwd
  end

  # Return an +Array+ of potential local tab-completions for a +String+.
  def self.local(string)
    dir = local_search_path(string)
    basename = basename(string)

    matches = Dir.entries(dir).select { |entry| match?(basename, entry) }
    matches.map do |entry|
      final_match(string, entry, File.directory?(dir + '/' + entry))
    end
  end

  # Return an +Array+ of potential local tab-completions for a +String+,
  # including only directories.
  def self.local_dir(string)
    local(string).select { |match| match.end_with?('/') }
  end

  # Return the directory in which to search for potential remote
  # tab-completions for a +String+.
  def self.remote_search_path(string, state)
    path = case
           when string.empty? then state.pwd + '/'
           when string.start_with?('/') then string
           else state.pwd + '/' + string
           end

    strip_filename(collapse(path))
  end

  # Return an +Array+ of potential remote tab-completions for a +String+.
  def self.remote(string, state)
    dir = remote_search_path(string, state)
    basename = basename(string)

    entries = state.contents(dir).map { |entry| File.basename(entry) }
    matches = entries.select { |entry| match?(basename, entry) }
    matches.map do |entry|
      final_match(string, entry, state.directory?(dir + '/' + entry))
    end
  end

  # Return an +Array+ of potential remote tab-completions for a +String+,
  # including only directories.
  def self.remote_dir(string, state)
    remote(string, state).select { |result| result.end_with?('/') }
  end

  private

  def self.basename(string)
    string.end_with?('/') ? '' : File.basename(string)
  end

  def self.match?(prefix, candidate)
    candidate.start_with?(prefix) && !candidate[/^\.\.?$/]
  end

  def self.final_match(string, candidate, is_dir)
    string + candidate.partition(basename(string))[2] + (is_dir ? '/' : ' ')
  end

  # Return the name of the directory indicated by a path.
  def self.strip_filename(path)
    return path if path == '/'
    path.end_with?('/') ? path.sub(/\/$/, '') : File.dirname(path)
  end

  # Return a version of a path with .. and . resolved to appropriate
  # directories.
  def self.collapse(path)
    new_path = path.dup
    nil while new_path.sub!(%r{[^/]+/\.\./}, '/')
    nil while new_path.sub!('./', '')
    new_path
  end
end
