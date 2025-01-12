# -*- coding: utf-8 -*-

require 'weakref'

module RobustExcelOle

  # This class essentially wraps a Win32Ole Workbook object. 
  # You can apply all VBA methods (starting with a capital letter) 
  # that you would apply for a Workbook object. 
  # See https://docs.microsoft.com/en-us/office/vba/api/excel.workbook#methods

  class Workbook < RangeOwners

    include Enumerable

    attr_reader :ole_workbook
    attr_reader :excel
    attr_reader :stored_filename

    alias ole_object ole_workbook

    using ToReoRefinement

    CORE_DEFAULT_OPEN_OPTS = {
      default: {excel: :current}, 
      force: {},
      update_links: :never 
    }.freeze

    DEFAULT_OPEN_OPTS = {
      if_unsaved: :raise,
      if_obstructed: :raise,
      if_absent: :raise,
      if_exists: :raise
    }.merge(CORE_DEFAULT_OPEN_OPTS).freeze  

    ABBREVIATIONS = [
      [:default,:d],
      [:force, :f],
      [:excel, :e],
      [:visible, :v],
      [:if_obstructed, :if_blocked]
    ].freeze


    # opens a workbook.
    # @param [String,Pathname] file_or_workbook a file name (string or pathname) or WIN32OLE workbook
    # @param [Hash] opts the options
    # @option opts [Hash] :default or :d
    # @option opts [Hash] :force or :f
    # @option opts [Symbol]  :if_unsaved     :raise (default), :forget, :save, :accept, :alert, :excel, or :new_excel
    # @option opts [Symbol]  :if_blocked     :raise (default), :forget, :save, :close_if_saved, or _new_excel
    # @option opts [Symbol]  :if_absent      :raise (default) or :create
    # @option opts [Boolean] :read_only      true (default) or false
    # @option opts [Boolean] :update_links   :never (default), :always, :alert
    # @option opts [Boolean] :calculation    :manual, :automatic, or nil (default)
    # options:
    # :default : if the workbook was already open before, then use (unchange) its properties,
    #            otherwise, i.e. if the workbook cannot be reopened, use the properties stated in :default
    # :force   : no matter whether the workbook was already open before, use the properties stated in :force
    # :default and :force contain: :excel
    #  :excel   :current (or :active or :reuse)
    #                    -> connects to a running (the first opened) Excel instance,
    #                       excluding the hidden Excel instance, if it exists,
    #                       otherwise opens in a new Excel instance.
    #           :new     -> opens in a new Excel instance
    #           <excel-instance> -> opens in the given Excel instance
    #  :visible true, false, or nil (default)
    #  alternatives: :default_excel, :force_excel, :visible, :d, :f, :e, :v
    # :if_unsaved     if an unsaved workbook with the same name is open, then
    #                  :raise               -> raise an exception
    #                  :forget              -> close the unsaved workbook, re-open the workbook
    #                  :accept              -> let the unsaved workbook open
    #                  :alert or :excel     -> give control to Excel
    #                  :new_excel           -> open the workbook in a new Excel instance
    # :if_obstructed  if a workbook with the same name in a different path is open, then
    # or               :raise               -> raise an exception
    # :if_blocked      :forget              -> close the workbook, re-open the workbook
    #                  :accept              -> let the blocked workbook open
    #                  :save                -> save the blocked workbook, close it, re-open the workbook
    #                  :close_if_saved      -> close the blocked workbook and re-open the workbook, if the blocked workbook is saved,
    #                                          otherwise raise an exception.
    #                  :new_excel           -> open the workbook in a new Excel instance
    # :if_absent       :raise               -> raise an exception     , if the file does not exists
    #                  :create              -> create a new Excel file, if it does not exists
    # :read_only            true -> open in read-only mode
    # :visible              true -> make the workbook visible
    # :check_compatibility  true -> check compatibility when saving
    # :update_links         true -> user is being asked how to update links, false -> links are never updated
    # @return [Workbook] a representation of a workbook   
    def self.new(file_or_workbook, opts = { })
      process_options(opts)
      case file_or_workbook
      when NilClass
        raise FileNameNotGiven, "filename is nil"
      when WIN32OLE
        begin
          file_or_workbook.send(:LinkSources)
          file = file_or_workbook.Fullname.tr('\\','/')
        rescue
          raise TypeREOError, "given win32ol object is not a workbook"
        end
      when Workbook
        file = file_or_workbook.Fullname.tr('\\','/')
      when String
        file = file_or_workbook
        raise FileNotFound, "file #{General.absolute_path(file).inspect} is a directory" if File.directory?(file)
      when ->(n){ n.respond_to? :to_path }
        file = file_or_workbook.to_path
        raise FileNotFound, "file #{General.absolute_path(file).inspect} is a directory" if File.directory?(file)
      else
        raise TypeREOError, "given object is neither a filename, a Win32ole, nor a Workbook object"
      end
      # try to fetch the workbook from the bookstore
      set_was_open opts, file_or_workbook.is_a?(WIN32OLE)
      book = nil
      if opts[:force][:excel] != :new
        # if readonly is true, then prefer a book that is given in force_excel if this option is set              
        forced_excel = begin
          (opts[:force][:excel].nil? || opts[:force][:excel] == :current) ? 
            (excel_class.new(reuse: true) if !::CONNECT_JRUBY_BUG) : opts[:force][:excel].to_reo.excel
        rescue NoMethodError
          raise TypeREOError, "provided Excel option value is neither an Excel object nor a valid option"
        end
        begin
          book = if File.exists?(file)
            bookstore.fetch(file, prefer_writable: !(opts[:read_only]),
                                  prefer_excel: (opts[:read_only] ? forced_excel : nil))
          end
        rescue
          raise
          #trace "#{$!.message}"
        end
        if book 
          set_was_open opts, book.alive?
          # drop the fetched workbook if it shall be opened in another Excel instance
          # or the workbook is an unsaved workbook that should not be accepted
          if (opts[:force][:excel].nil? || opts[:force][:excel] == :current || forced_excel == book.excel) &&
            !(book.alive? && !book.saved && (opts[:if_unsaved] != :accept))
            opts[:force][:excel] = book.excel if book.excel && book.excel.alive?
            book.ensure_workbook(file,opts)
            book.send :apply_options, file, opts
            return book
          end
        end
      end        
      super(file_or_workbook, opts)
    end

    singleton_class.send :alias_method, :open, :new

    # creates a new Workbook object, if a file name is given
    # Promotes the win32ole workbook to a Workbook object, if a win32ole-workbook is given
    # @param [Variant] file_or_workbook  file name or workbook
    # @param [Hash]    opts             
    # @option opts [Symbol] see above
    # @return [Workbook] a workbook
    def initialize(file_or_workbook, opts)
      if file_or_workbook.is_a? WIN32OLE
        @ole_workbook = file_or_workbook
        ole_excel = begin 
          @ole_workbook.Application
        rescue WIN32OLERuntimeError
          raise ExcelREOError, "could not determine the Excel instance\n#{$!.message}"
        end
        @excel = excel_class.new(ole_excel)
        file_name = @ole_workbook.Fullname.tr('\\','/') 
      else
        file_name = file_or_workbook
        ensure_workbook(file_name, opts)        
      end      
      apply_options(file_name, opts)
      store_myself
      if block_given?
        begin
          yield self
        ensure
          close
        end
      end
    end
 
  private    

    def self.set_was_open(hash, value)
      hash[:was_open] = value if hash.has_key?(:was_open)
    end

    def set_was_open(hash, value)
      self.class.set_was_open(hash, value)
    end

    def self.process_options(opts, proc_opts = {use_defaults: true})
      translate(opts)
      default_opts = (proc_opts[:use_defaults] ? DEFAULT_OPEN_OPTS : CORE_DEFAULT_OPEN_OPTS).dup
      translate(default_opts)
      opts.merge!(default_opts) { |key, v1, v2| !v2.is_a?(Hash) ? v1 : v2.merge(v1 || {}) }
    end

    def self.translate(opts)
      erg = {}
      opts.each do |key,value|
        new_key = key
        ABBREVIATIONS.each { |long,short| new_key = long if key == short }
        if value.is_a?(Hash)
          erg[new_key] = {}
          value.each do |k,v|
            new_k = k
            ABBREVIATIONS.each { |l,s| new_k = l if k == s }
            erg[new_key][new_k] = v
          end
        else
          erg[new_key] = value
        end
      end
      opts.merge!(erg)
      opts[:default] ||= {}
      opts[:force] ||= {}
      force_list = [:visible, :excel]
      opts.each { |key,value| opts[:force][key] = value if force_list.include?(key) }
      opts[:default][:excel] = opts[:default_excel] unless opts[:default_excel].nil?
      opts[:force][:excel] = opts[:force_excel] unless opts[:force_excel].nil?
      opts[:default][:excel] = :current if opts[:default][:excel] == :reuse || opts[:default][:excel] == :active
      opts[:force][:excel] = :current if opts[:force][:excel] == :reuse || opts[:force][:excel] == :active
    end

  public

    # @private
    # ensures an excel but not for jruby if current Excel shall be used
    def ensure_excel(options)
      return if @excel && @excel.alive?
      excel_option = options[:force][:excel] || options[:default][:excel] || :current
      @excel = if excel_option == :new
        excel_class.new(reuse: false) 
      elsif excel_option == :current
        excel_class.new(reuse: true)
      elsif excel_option.respond_to?(:to_reo)
        excel_option.to_reo.excel
      else
        raise TypeREOError, "provided Excel option value is neither an Excel object nor a valid option"
      end
      raise ExcelREOError, "Excel is not alive" unless @excel && @excel.alive?
    end

    # @private    
    def ensure_workbook(file_name, options)
      set_was_open options, true
      return if (@ole_workbook && alive? && (options[:read_only].nil? || @ole_workbook.ReadOnly == options[:read_only]))
      set_was_open options, false
      if options[:if_unsaved]==:accept && alive? && 
        ((options[:read_only]==true && self.ReadOnly==false) || (options[:read_only]==false && self.ReadOnly==true))
        raise OptionInvalid, ":if_unsaved:accept and change of read-only mode is not possible"
      end
      file_name = @stored_filename ? @stored_filename : file_name 
      manage_nonexisting_file(file_name,options)
      excel_option = options[:force][:excel].nil? ? options[:default][:excel] : options[:force][:excel]        
      ensure_excel(options)
      workbooks = @excel.Workbooks
      @ole_workbook = workbooks.Item(File.basename(file_name)) rescue nil if @ole_workbook.nil?
      if @ole_workbook && alive?
        set_was_open options, true
        #open_or_create_workbook(file_name,options) if (!options[:read_only].nil?) && options[:read_only] 
        manage_changing_readonly_mode(file_name, options) if (!options[:read_only].nil?) && options[:read_only] != @ole_workbook.ReadOnly
        manage_blocking_or_unsaved_workbook(file_name,options)
      else
        if (excel_option.nil? || excel_option == :current) &&  
          !(::CONNECT_JRUBY_BUG && file_name[0] == '/')
          connect(file_name,options)
        else 
          open_or_create_workbook(file_name,options)
        end
      end       
    end

  private

    # applies options to workbook named with file_name
    def apply_options(file_name, options)
      # changing read-only mode      
      if (!options[:read_only].nil?) && options[:read_only] != @ole_workbook.ReadOnly
        # ensure_workbook(file_name, options) 
        manage_changing_readonly_mode(file_name, options)
      end
      retain_saved do
        self.visible = options[:force][:visible].nil? ? @excel.Visible : options[:force][:visible]
        @excel.calculation = options[:calculation] unless options[:calculation].nil?
        @ole_workbook.CheckCompatibility = options[:check_compatibility] unless options[:check_compatibility].nil?
      end      
    end

    # connects to an unknown workbook
    def connect(file_name, options)   
      workbooks_number = excel_class.instance_count==0 ? 0 : excel_class.current.Workbooks.Count
      @ole_workbook = begin
        WIN32OLE.connect(General.absolute_path(file_name))
      rescue
        if $!.message =~ /moniker/
          raise WorkbookConnectingBlockingError, "some workbook is blocking when connecting"
        else 
          raise WorkbookConnectingUnknownError, "unknown error when connecting to a workbook\n#{$!.message}"
        end
      end
      ole_excel = begin
        @ole_workbook.Application     
      rescue 
        if $!.message =~ /dispid/
          raise WorkbookConnectingUnsavedError, "workbook is unsaved when connecting"
        else 
          raise WorkbookConnectingUnknownError, "unknown error when connecting to a workbook\n#{$!.message}"
        end
      end
      set_was_open options, (ole_excel.Workbooks.Count == workbooks_number)
      @excel = excel_class.new(ole_excel)
    end

    def manage_changing_readonly_mode(file_name, options)
      if !ole_workbook.Saved && options[:read_only]      
        manage_unsaved_workbook_when_changing_readonly_mode(options) 
      end
      change_readonly_mode(file_name, options)
    end

    def change_readonly_mode(file_name, options)
      read_write_value = options[:read_only] ? RobustExcelOle::XlReadOnly : RobustExcelOle::XlReadWrite
      give_control_to_excel = !ole_workbook.Saved && options[:read_only] && 
                              (options[:if_unsaved] == :excel || options[:if_unsaved] == :alert)
      displayalerts = give_control_to_excel ? true : @excel.Displayalerts
      # applying ChangeFileAccess to a linked unsaved workbook to change to read-write 
      # causes a query
      # how to check whether the workbook contains links?
      #if options[:read_only]==false && !@ole_workbook.Saved # && @ole_workbook.LinkSources(RobustExcelOle::XlExcelLinks) # workbook linked
      #  # @ole_workbook.Saved = true
      #  raise WorkbookNotSaved, "linked workbook cannot be changed to read-write if it is unsaved"
      #end
      @excel.with_displayalerts(displayalerts) {
        begin
          @ole_workbook.ChangeFileAccess('Mode' => read_write_value)
      rescue WIN32OLERuntimeError
        raise WorkbookReadOnly, "cannot change read-only mode"
      end
      }
      # managing Excel bug:
      # if the workbook is linked, then ChangeFileAccess to read-write kills the workbook  
      # if the linked workbook is unsaved, then ChangeFileAccess causes a query
      # this query cannot be avoided or controlled so far (see above)
      open_or_create_workbook(file_name, options) unless alive?
    end

    def manage_unsaved_workbook_when_changing_readonly_mode(options)
      case options[:if_unsaved] 
      when :raise
        if options[:read_only]        
          raise WorkbookNotSaved, "workbook is not saved" +
          "\nHint: Use the option :if_unsaved with values :forget or :save,
          to allow changing to ReadOnly mode (with discarding or saving the workbook before, respectively),
          or option :excel to give control to Excel."
        end
      when :save 
        save
      when :forget
        @ole_workbook.Saved = true
      when :alert, :excel
        # displayalerts = true
        # nothing
      else
        raise OptionInvalid, ":if_unsaved: invalid option: #{options[:if_unsaved].inspect}" +
        "\nHint: Valid values are :raise, :forget, :save, :excel"
      end
    end

    def manage_nonexisting_file(file_name, options)   
      return if File.exist?(file_name)
      abs_filename = General.absolute_path(file_name)
      if options[:if_absent] == :create
        ensure_excel(options) unless @excel && @excel.alive?
        @excel.Workbooks.Add
        empty_ole_workbook = excel.Workbooks.Item(excel.Workbooks.Count)
        begin
          empty_ole_workbook.SaveAs(abs_filename)
        rescue WIN32OLERuntimeError, Java::OrgRacobCom::ComFailException => msg
          raise FileNotFound, "could not save workbook with filename #{file_name.inspect}"
        end
      else
        raise FileNotFound, "file #{abs_filename.inspect} not found" +
          "\nHint: If you want to create a new file, use option :if_absent => :create or Workbook::create"
      end
    end

    def manage_blocking_or_unsaved_workbook(file_name, options)
      file_name = General.absolute_path(file_name)
      file_name = General.canonize(file_name)
      previous_file = General.canonize(@ole_workbook.Fullname.gsub('\\','/'))
      obstructed_by_other_book = (File.basename(file_name) == File.basename(previous_file)) &&
                                 (File.dirname(file_name) != File.dirname(previous_file)) 
      if obstructed_by_other_book
        # workbook is being obstructed by a workbook with same name and different path
        manage_blocking_workbook(file_name,options)        
      else
        unless @ole_workbook.Saved
          # workbook open and writable, not obstructed by another workbook, but not saved
          manage_unsaved_workbook(file_name,options)
        end
      end        
    end

    def manage_blocking_workbook(file_name, options)     
      blocked_filename = -> { General.canonize(@ole_workbook.Fullname.tr('\\','/')) }
      case options[:if_obstructed]
      when :raise
        raise WorkbookBlocked, "can't open workbook #{file_name},
        because it is being blocked by #{blocked_filename.call} with the same name in a different path." +
        "\nHint: Use the option :if_blocked with values :forget or :save,
         to allow automatic closing of the blocking workbook (without or with saving before, respectively),
         before reopening the workbook."
      when :forget
        manage_forgetting_workbook(file_name, options)       
      when :accept
        # do nothing
      when :save
        manage_saving_workbook(file_name, options)        
      when :close_if_saved
        if !@ole_workbook.Saved
          raise WorkbookBlocked, "workbook with the same name in a different path is unsaved: #{blocked_filename.call}" +
          "\nHint: Use the option if_blocked: :save to save the workbook"
        else
          manage_forgetting_workbook(file_name, options)
        end
      when :new_excel
        manage_new_excel(file_name, options)        
      else
        raise OptionInvalid, ":if_blocked: invalid option: #{options[:if_obstructed].inspect}" +
        "\nHint: Valid values are :raise, :forget, :save, :close_if_saved, :new_excel"
      end
    end

    def manage_unsaved_workbook(file_name, options)
      case options[:if_unsaved]
      when :raise
        raise WorkbookNotSaved, "workbook is already open but not saved: #{File.basename(file_name).inspect}" +
        "\nHint: Use the option :if_unsaved with values :forget to close the unsaved workbook, 
         :accept to let it open, or :save to save it, respectivly"
      when :forget
        manage_forgetting_workbook(file_name, options)
      when :accept
        # do nothing
      when :save
        manage_saving_workbook(file_name, options)
      when :alert, :excel
        @excel.with_displayalerts(true) { open_or_create_workbook(file_name,options) }
      when :new_excel
        manage_new_excel(file_name, options)
      else
        raise OptionInvalid, ":if_unsaved: invalid option: #{options[:if_unsaved].inspect}" +
        "\nHint: Valid values are :raise, :forget, :save, :accept, :alert, :excel, :new_excel"
      end
    end

    def manage_forgetting_workbook(file_name, options)
      @excel.with_displayalerts(false) { @ole_workbook.Close }
      @ole_workbook = nil
      open_or_create_workbook(file_name, options)
    end

    def manage_saving_workbook(file_name, options)
      save unless @ole_workbook.Saved
      manage_forgetting_workbook(file_name, options) if options[:if_obstructed] == :save
    end

    def manage_new_excel(file_name, options)
      @excel = excel_class.new(reuse: false)
      @ole_workbook = nil
      open_or_create_workbook(file_name, options)
    end

    def explore_workbook_error(msg, want_change_readonly = nil)
      if msg.message =~ /800A03EC/ && msg.message =~ /0x80020009/
        # error message: 
        # 'This workbook is currently referenced by another workbook and cannot be closed'
        # 'Diese Arbeitsmappe wird momentan von einer anderen Arbeitsmappe verwendet und kann nicht geschlossen werden.'
        if want_change_readonly==true
          raise WorkbookLinked, "read-only mode of this workbook cannot be changed, because it is being used by another workbook"
        elsif want_change_readonly.nil?
          raise WorkbookLinked, "workbook is being used by another workbook"
        end
      end
      if msg.message !~ /800A03EC/ || msg.message !~ /0x80020009/ || want_change_readonly==false
        raise UnexpectedREOError, "unknown WIN32OLERuntimeError:\n#{msg.message}"
      end
    end

    def open_or_create_workbook(file_name, options)
      return if @ole_workbook && options[:if_unsaved] != :alert && options[:if_unsaved] != :excel &&
                (options[:read_only].nil? || options[:read_only]==@ole_workbook.ReadOnly )
      abs_filename = General.absolute_path(file_name)
      workbooks = begin 
        @excel.Workbooks
      rescue WIN32OLERuntimeError, Java::OrgRacobCom::ComFailException => msg
        raise UnexpectedREOError, "cannot access workbooks: #{msg.message} #{msg.backtrace}"
      end
      begin
        with_workaround_linked_workbooks_excel2007(options) do
          # temporary workaround until jruby-win32ole implements named parameters (Java::JavaLang::RuntimeException (createVariant() not implemented for class org.jruby.RubyHash)
          workbooks.Open(abs_filename, updatelinks_vba(options[:update_links]), options[:read_only] )
        end
      rescue WIN32OLERuntimeError, Java::OrgRacobCom::ComFailException => msg
        # for Excel2007: for option :if_unsaved => :alert and user cancels: this error appears?; distinguish these events
        want_change_readonly = !options[:read_only].nil? && (options[:read_only] != @ole_workbook.ReadOnly)
      end
      # workaround for bug in Excel 2010: workbook.Open does not always return the workbook when given file name
      @ole_workbook = begin
        workbooks.Item(File.basename(file_name))
      rescue WIN32OLERuntimeError, Java::OrgRacobCom::ComFailException => msg
        raise UnexpectedREOError, "WIN32OLERuntimeError: #{msg.message}"
      end
    end  

    # translating the option UpdateLinks from REO to VBA
    # setting UpdateLinks works only if calculation mode is automatic,
    # parameter 'UpdateLinks' has no effect
    def updatelinks_vba(updatelinks_reo)
      case updatelinks_reo
      when :alert  then RobustExcelOle::XlUpdateLinksUserSetting
      when :never  then RobustExcelOle::XlUpdateLinksNever
      when :always then RobustExcelOle::XlUpdateLinksAlways
      else              RobustExcelOle::XlUpdateLinksNever
      end
    end

    # workaround for linked workbooks for Excel 2007:
    # opening and closing a dummy workbook if Excel has no workbooks.
    # delay: with visible: 0.2 sec, without visible almost none
    def with_workaround_linked_workbooks_excel2007(options)
      old_visible_value = @excel.Visible
      workbooks = @excel.Workbooks
      workaround_condition = @excel.Version.split('.').first.to_i == 12 && workbooks.Count == 0
      if workaround_condition
        workbooks.Add
        @excel.calculation = options[:calculation].nil? ? @excel.properties[:calculation] : options[:calculation]
      end
      begin
        # @excel.with_displayalerts(update_links_opt == :alert ? true : @excel.displayalerts) do
        yield self
      ensure
        @excel.with_displayalerts(false) { workbooks.Item(1).Close } if workaround_condition
        @excel.visible = old_visible_value
      end
    end

  public

    # creates, i.e., opens a new, empty workbook, and saves it under a given filename
    # @param [String] filename the filename under which the new workbook should be saved
    # @param [Hash] opts the options as in Workbook::open
    def self.create(file_name, opts = { })
      open(file_name, if_absent: :create)
    end

    # closes the workbook, if it is alive
    # @param [Hash] opts the options
    # @option opts [Symbol] :if_unsaved :raise (default), :save, :forget, :keep_open, or :alert
    # options:
    #  :if_unsaved    if the workbook is unsaved
    #                      :raise           -> raise an exception
    #                      :save            -> save the workbook before it is closed
    #                      :forget          -> close the workbook
    #                      :keep_open       -> keep the workbook open
    #                      :alert or :excel -> give control to excel
    # @raise WorkbookNotSaved if the option :if_unsaved is :raise and the workbook is unsaved
    # @raise OptionInvalid if the options is invalid
    def close(opts = {if_unsaved: :raise})
      return close_workbook unless (alive? && !@ole_workbook.Saved && writable)
      case opts[:if_unsaved]
      when :raise
        raise WorkbookNotSaved, "workbook is unsaved: #{File.basename(self.stored_filename).inspect}" +
        "\nHint: Use option :save or :forget to close the workbook with or without saving"
      when :save
        save
        close_workbook
      when :forget
        @excel.with_displayalerts(false) { close_workbook }
      when :keep_open
        # nothing
      when :alert, :excel
        @excel.with_displayalerts(true) { close_workbook }
      else
        raise OptionInvalid, ":if_unsaved: invalid option: #{opts[:if_unsaved].inspect}" +
        "\nHint: Valid values are :raise, :save, :keep_open, :alert, :excel"
      end
    end

  private

    def close_workbook
      if alive?
        begin
          @ole_workbook.Close 
        rescue WIN32OLERuntimeError, Java::OrgRacobCom::ComFailException => msg
          explore_workbook_error(msg)          
        end
      end      
      @ole_workbook = nil unless alive?
    end

  public

    # keeps the saved-status unchanged
    def retain_saved
      saved = self.Saved
      begin
        yield self
      ensure
        self.Saved = saved
      end
    end

    def for_reading(opts = { }, &block)
      unobtrusively({writable: false}.merge(opts), &block)
    end

    def for_modifying(opts = { }, &block)
      unobtrusively({writable: true}.merge(opts), &block)
    end

    def self.for_reading(arg, opts = { }, &block)
      unobtrusively(arg, {writable: false}.merge(opts), &block)
    end

    def self.for_modifying(arg, opts = { }, &block)
      unobtrusively(arg, {writable: true}.merge(opts), &block)
    end

    # allows to read or modify a workbook such that its state remains unchanged
    # state comprises: open, saved, writable, visible, calculation mode, check compatibility
    # @param [String] file_or_workbook     a file name or WIN32OLE workbook
    # @param [Hash]   opts        the options   
    # @option opts [Boolean] :read_only true/false (default), force to open the workbook in read-only/read-write mode
    # @option opts [Boolean] :writable  true (default)/false changes of the workbook shall be saved/not saved, 
    #                                   and the workbook is being opened in read-only/read-write mode by default 
    #                                   (when the workbook was not open before)
    # @option opts [Boolean] :keep_open whether the workbook shall be kept open after unobtrusively opening (default: false)
    # @option opts [Variant] :if_closed  :current (default), :new or an Excel instance
    # @return [Workbook] a workbook
    def self.unobtrusively(file_or_workbook, opts = { }, &block)
      file = (file_or_workbook.is_a? WIN32OLE) ? file_or_workbook.Fullname.tr('\\','/') : file_or_workbook
      unobtrusively_opening(file, opts, nil, &block)
    end

    def unobtrusively(opts = { }, &block)
      file = @stored_filename
      self.class.unobtrusively_opening(file, opts, alive?, &block)
    end

  private

    def self.unobtrusively_opening(file, opts, book_is_alive, &block)
      process_options(opts)
      opts = {if_closed: :current, keep_open: false}.merge(opts)    
      raise OptionInvalid, "contradicting options" if opts[:writable] && opts[:read_only] 
      if book_is_alive.nil?
        prefer_writable = ((!(opts[:read_only]) || opts[:writable] == true) &&
                           !(opts[:read_only].nil? && opts[:writable] == false))
        known_book = bookstore.fetch(file, prefer_writable: prefer_writable) 
      end
      excel_opts = if (book_is_alive==false || (book_is_alive.nil? && (known_book.nil? || !known_book.alive?)))
        {force: {excel: opts[:if_closed]}}
      else
        {force: {excel: opts[:force][:excel]}, default: {excel: opts[:default][:excel]}}
      end
      open_opts = excel_opts.merge({if_unsaved: :accept})
      begin
        open_opts[:was_open] = nil  
        book = open(file, open_opts)
        was_visible = book.visible
        was_saved = book.saved
        was_check_compatibility = book.check_compatibility
        was_calculation = book.excel.properties[:calculation]
        was_writable = book.writable
        if (opts[:read_only].nil? && !opts[:writable].nil? && !open_opts[:was_open] && (was_saved || opts[:if_unsaved]==:save))
          opts[:read_only] = !opts[:writable]
        end
        book.send :apply_options, file, opts
        yield book
      ensure
        if book && book.alive?
          was_open = open_opts[:was_open]
          do_not_write = opts[:read_only] || opts[:writable]==false
          book.save unless book.saved || do_not_write || !book.writable
          if was_open && ((opts[:read_only] && was_writable) || (!opts[:read_only] && !was_writable))
            book.send :apply_options, file, opts.merge({read_only: !was_writable, 
                                            if_unsaved: (opts[:writable]==false ? :forget : :save)})
          end
          #was_open = open_opts[:was_open]
          if was_open
            book.visible = was_visible    
            book.CheckCompatibility = was_check_compatibility
            book.excel.calculation = was_calculation
          end
          book.Saved = (was_saved || !was_open)
          book.close unless was_open || opts[:keep_open]
        end
      end
    end

  public 

    # reopens a closed workbook
    # @options options
    def open(options = { })
      book = self.class.open(@stored_filename, options)
      raise WorkbookREOError("cannot reopen workbook\n#{$!.message}") unless book && book.alive?
      book
    end

    alias reopen open   # :deprecated: #

    # simple save of a workbook.
    # @return [Boolean] true, if successfully saved, nil otherwise
    def save(opts = { })  # option opts is deprecated #
      raise ObjectNotAlive, "workbook is not alive" unless alive?
      raise WorkbookReadOnly, "Not opened for writing (opened with :read_only option)" if @ole_workbook.ReadOnly   
      begin
        @ole_workbook.Save
      rescue WIN32OLERuntimeError, Java::OrgRacobCom::ComFailException => msg
        if msg.message =~ /SaveAs/ && msg.message =~ /Workbook/
          raise WorkbookNotSaved, "workbook not saved"
        else
          raise UnexpectedREOError, "unknown WIN32OLERuntimeError:\n#{msg.message}"
        end
      end
      true
    end

    # saves a workbook with a given file name.
    # @param [String] file   file name
    # @param [Hash]   opts   the options
    # @option opts [Symbol] :if_exists      :raise (default), :overwrite, or :alert, :excel
    # @option opts [Symbol] :if_obstructed  :raise (default), :forget, :save, or :close_if_saved
    # options:
    # :if_exists  if a file with the same name exists, then
    #               :raise     -> raises an exception, dont't write the file  (default)
    #               :overwrite -> writes the file, delete the old file
    #               :alert or :excel -> gives control to Excel
    #  :if_obstructed   if a workbook with the same name and different path is already open and blocks the saving, then
    #  or              :raise               -> raise an exception
    #  :if_blocked     :forget              -> close the blocking workbook
    #                  :save                -> save the blocking workbook and close it
    #                  :close_if_saved      -> close the blocking workbook, if it is saved,
    #                                          otherwise raises an exception   
    # @return [Workbook], the book itself, if successfully saved, raises an exception otherwise
    def save_as(file, options = { })
      raise FileNameNotGiven, "filename is nil" if file.nil?
      raise ObjectNotAlive, "workbook is not alive" unless alive?
      raise WorkbookReadOnly, "Not opened for writing (opened with :read_only option)" if @ole_workbook.ReadOnly
      raise(FileNotFound, "file #{General.absolute_path(file).inspect} is a directory") if File.directory?(file)
      self.class.process_options(options)
      begin  
        saveas_manage_if_exists(file, options)
        saveas_manage_if_blocked(file, options)
        save_as_workbook(file, options)
      rescue AlreadyManaged
        nil
      end
      self
    end

  private

    def saveas_manage_if_exists(file, options)
      return unless File.exist?(file)
      case options[:if_exists]
      when :overwrite
        if file == self.filename
          save
          raise AlreadyManaged
        else
          begin
            File.delete(file)
          rescue Errno::EACCES
            raise WorkbookBeingUsed, "workbook is open and being used in an Excel instance"
          end
        end
      when :alert, :excel
        @excel.with_displayalerts(true){ save_as_workbook(file, options) }
        raise AlreadyManaged
      when :raise
        raise FileAlreadyExists, "file already exists: #{File.basename(file).inspect}" +
        "\nHint: Use option if_exists: :overwrite, if you want to overwrite the file" 
      else
        raise OptionInvalid, ":if_exists: invalid option: #{options[:if_exists].inspect}" +
        "\nHint: Valid values are :raise, :overwrite, :alert, :excel"
      end
    end

    def saveas_manage_if_blocked(file, options)
      other_workbook = @excel.Workbooks.Item(File.basename(file)) rescue nil
      return unless other_workbook && self.filename != other_workbook.Fullname.tr('\\','/')
      case options[:if_obstructed]
      when :raise
        raise WorkbookBlocked, "blocked by another workbook: #{other_workbook.Fullname.tr('\\','/')}" +
        "\nHint: Use the option :if_blocked with values :forget or :save to
         close or save and close the blocking workbook"
      when :forget
        # nothing
      when :save
        other_workbook.Save
      when :close_if_saved
        unless other_workbook.Saved
          raise WorkbookBlocked, "blocking workbook is unsaved: #{File.basename(file).inspect}" +
          "\nHint: Use option if_blocked: :save to save the blocking workbooks"
        end
      else
        raise OptionInvalid, "if_blocked: invalid option: #{options[:if_obstructed].inspect}" +
        "\nHint: Valid values are :raise, :forget, :save, :close_if_saved"
      end
      other_workbook.Close
    end

    def save_as_workbook(file, options)  
      dirname, basename = File.split(file)
      file_format =
        case File.extname(basename)
        when '.xls' then RobustExcelOle::XlExcel8
        when '.xlsx' then RobustExcelOle::XlOpenXMLWorkbook
        when '.xlsm' then RobustExcelOle::XlOpenXMLWorkbookMacroEnabled
        end
      @ole_workbook.SaveAs(General.absolute_path(file), file_format)
      store_myself
    rescue WIN32OLERuntimeError, Java::OrgRacobCom::ComFailException => msg
      if msg.message =~ /SaveAs/ && msg.message =~ /Workbook/
        # trace "save: canceled by user" if options[:if_exists] == :alert || options[:if_exists] == :excel
        # another possible semantics. raise WorkbookREOError, "could not save Workbook"
      else
        raise UnexpectedREOError, "unknown WIN32OELERuntimeError:\n#{msg.message}"
      end
    end

    class AlreadyManaged < Exception
    end

    def store_myself
      bookstore.store(self)
      @stored_filename = filename
    end

  public

    # closes a given file if it is open
    # @options opts [Symbol] :if_unsaved
    def self.close(file, opts = {if_unsaved: :raise})
      book = begin
        bookstore.fetch(file)
        rescue
          nil
        end
      book.close(opts) if book && book.alive?
    end

    # saves a given file if it is open
    def self.save(file)
      book = bookstore.fetch(file) rescue nil
      book.save if book && book.alive?
    end

    # saves a given file under a new name if it is open
    def self.save_as(file, new_file, opts = { })
      book = begin
        bookstore.fetch(file)
      rescue 
        nil
      end
      book.save_as(new_file, opts) if book && book.alive?
    end

    # returns a sheet, if a sheet name or a number is given
    # @param [String] or [Number]
    # @returns [Worksheet]
    def sheet(name)
      worksheet_class.new(@ole_workbook.Worksheets.Item(name))
    rescue WIN32OLERuntimeError, Java::OrgRacobCom::ComFailException => msg
      raise NameNotFound, "could not return a sheet with name #{name.inspect}"
    end

    def worksheets_count
      @ole_workbook.Worksheets.Count
    end

    # @return [Enumerator] traversing all worksheet objects
    def each
      if block_given?
        @ole_workbook.Worksheets.lazy.each do |ole_worksheet|
          yield worksheet_class.new(ole_worksheet)
        end
      else
        to_enum(:each).lazy
      end
    end

    def each_with_index(offset = 0)
      i = offset
      @ole_workbook.Worksheets.lazy.each do |sheet|
        yield worksheet_class.new(sheet), i
        i += 1
      end
    end

    # copies a sheet to another position if a sheet is given, or adds an empty sheet
    # default: copied or empty sheet is appended, i.e. added behind the last sheet
    # @param [Worksheet] sheet a sheet that shall be copied (optional)
    # @param [Hash]  opts  the options
    # @option opts [Symbol] :as     new name of the copied or added sheet
    # @option opts [Symbol] :before a sheet before which the sheet shall be inserted
    # @option opts [Symbol] :after  a sheet after which the sheet shall be inserted
    # @return [Worksheet] the copied or added sheet
    def add_or_copy_sheet(sheet = nil, opts = { })
      if sheet.is_a? Hash
        opts = sheet
        sheet = nil
      end
      begin
        sheet = sheet.to_reo unless sheet.nil?
        new_sheet_name = opts.delete(:as)
        last_sheet_local = last_sheet
        after_or_before, base_sheet = opts.to_a.first || [:after, last_sheet_local]
        base_sheet_ole = base_sheet.to_reo.ole_worksheet
        if !::COPYSHEETS_JRUBY_BUG          
          add_or_copy_sheet_simple(sheet, { after_or_before.to_s => base_sheet_ole })
        else
          if after_or_before == :before 
            add_or_copy_sheet_simple(sheet, base_sheet_ole)
          else
            if base_sheet.name != last_sheet_local.name
              add_or_copy_sheet_simple(sheet, base_sheet.Next)
            else
              add_or_copy_sheet_simple(sheet, base_sheet_ole)
              base_sheet.Move(ole_workbook.Worksheets.Item(ole_workbook.Worksheets.Count-1))
              ole_workbook.Worksheets.Item(ole_workbook.Worksheets.Count).Activate
            end
          end
        end
      rescue # WIN32OLERuntimeError, NameNotFound, Java::OrgRacobCom::ComFailException
        raise WorksheetREOError, "could not add given worksheet #{sheet.inspect}\n#{$!.message}"
      end
      new_sheet = worksheet_class.new(ole_workbook.Activesheet)
      new_sheet.name = new_sheet_name if new_sheet_name
      new_sheet
    end

  private
  
    def add_or_copy_sheet_simple(sheet, base_sheet_ole_or_hash)
      if sheet
        sheet.Copy(base_sheet_ole_or_hash)  
      else
        ole_workbook.Worksheets.Add(base_sheet_ole_or_hash) 
      end
    end 

  public

    # for compatibility to older versions
    def add_sheet(sheet = nil, opts = { })  # :deprecated: #
      add_or_copy_sheet(sheet, opts)
    end

    # for compatibility to older versions    
    def copy_sheet(sheet, opts = { })       # :deprecated: #
      add_or_copy_sheet(sheet, opts)
    end

    def last_sheet
      worksheet_class.new(@ole_workbook.Worksheets.Item(@ole_workbook.Worksheets.Count))
    end

    def first_sheet
      worksheet_class.new(@ole_workbook.Worksheets.Item(1))
    end

    # creates a range from a given defined name or from a given worksheet and address
    # @params [Variant] defined name or a worksheet
    # @params [Address] address
    # @return [Range] a range
    def range(name_or_worksheet, name_or_address = :__not_provided, address2 = :__not_provided)
      if name_or_worksheet.respond_to?(:gsub)
        name = name_or_worksheet
        RobustExcelOle::Range.new(get_name_object(name).RefersToRange)
      else 
        begin 
          worksheet = name_or_worksheet.to_reo
          worksheet.range(name_or_address, address2)
        rescue
          raise RangeNotCreated, "argument error: a defined name or a worksheet and an address must be provided"
        end          
      end
    end

    # returns the value of a range
    # @param [String] name the name of a range
    # @returns [Variant] the value of the range
    def [] name
      namevalue_global(name)
    end

    # sets the value of a range
    # @param [String]  name  the name of the range
    # @param [Variant] value the contents of the range
    def []= (name, value)
      set_namevalue_global(name, value)   
    end

    # sets options
    # @param [Hash] opts
    def for_this_workbook(opts)
      return unless alive?
      self.class.process_options(opts, use_defaults: false)
      self.send :apply_options, @stored_filename, opts
    end

    # brings workbook to foreground, makes it available for heyboard inputs, makes the Excel instance visible
    def focus
      self.visible = true
      @excel.focus
      @ole_workbook.Activate
    end

    # returns true, if the workbook reacts to methods, false otherwise
    def alive?
      @ole_workbook.Name
      true
    rescue
      @ole_workbook = nil  # dead object won't be alive again
      false
    end

    # returns the full file name of the workbook
    def filename
      General.canonize(@ole_workbook.Fullname.tr('\\','/')) rescue nil
    end

    # @returns true, if the workbook is not in read-only mode
    def writable   
      !@ole_workbook.ReadOnly if @ole_workbook
    end

    # sets the writable mode
    # @param [Bool] writable mode (true: read-write-mode, false: read-only mode)
    # @options [Symbol] :if_unsaved     if the workbook is unsaved, then
    #                    :raise               -> raise an exception (default)
    #                    :forget              -> close the unsaved workbook, re-open the workbook
    #                    :accept              -> let the unsaved workbook open
    #                    :alert or :excel     -> give control to Excel
    def writable=(value_and_opts)
      writable_value, unsaved_opts = *value_and_opts
      if @ole_workbook && !value_and_opts.nil?
        options = {:if_unsaved => :raise}
        options = options.merge(unsaved_opts) if unsaved_opts
        options = {:read_only => !writable_value}.merge(options)
        if options[:read_only] != @ole_workbook.ReadOnly
          manage_changing_readonly_mode(filename, options) 
          manage_unsaved_workbook(filename,options) if !@ole_workbook.Saved && unsaved_opts
        end
      end
      writable_value
    end


    # @private
    def saved  
      @ole_workbook.Saved if @ole_workbook
    end

    def calculation
      @excel.properties[:calculation] if @ole_workbook
    end

    # @private
    def check_compatibility
      @ole_workbook.CheckCompatibility if @ole_workbook
    end

    # returns true, if the workbook is visible, false otherwise
    def visible
      @excel.Visible && @ole_workbook.Windows(@ole_workbook.Name).Visible
    end

    # makes both the Excel instance and the window of the workbook visible, or the window invisible
    # does not do anything if geben visible_value is nil
    # @param [Boolean] visible_value determines whether the workbook shall be visible
    def visible= visible_value
      return if visible_value.nil?
      @excel.visible = true if visible_value
      self.window_visible = @excel.Visible ? visible_value : true
    end

    # returns true, if the window of the workbook is set to visible, false otherwise
    def window_visible
      @ole_workbook.Windows(@ole_workbook.Name).Visible
    end

    # makes the window of the workbook visible or invisible
    # @param [Boolean] visible_value determines whether the window of the workbook shall be visible
    def window_visible= visible_value
      retain_saved do
        @ole_workbook.Windows(@ole_workbook.Name).Visible = visible_value if @ole_workbook.Windows.Count > 0
      end
    end

    # @return [Boolean] true, if the full workbook names and excel Instances are identical, false otherwise
    def == other_book
      other_book.is_a?(Workbook) &&
        @excel == other_book.excel &&
        self.filename == other_book.filename
    end

    # @private
    def self.books
      bookstore.books
    end

    # @private
    def self.bookstore   
      @@bookstore ||= Bookstore.new
    end

    # @private
    def bookstore    
      self.class.bookstore
    end

    # @private
    def workbook
      self
    end

    # @private
    def to_s    
      self.filename.to_s
    end

    # @private
    def inspect    
      #{}"#<Workbook: #{("not alive " unless alive?)} #{(File.basename(self.filename) if alive?)} #{@excel}>"
      "#<Workbook: #{(alive? ? File.basename(self.filename) : "not alive")} #{@excel} >"
    end

    using ParentRefinement
    using StringRefinement

    # @private
    def self.excel_class    
      @excel_class ||= begin
        module_name = self.parent_name
        "#{module_name}::Excel".constantize        
      rescue NameError => e
        # trace "excel_class: NameError: #{e}"
        Excel
      end
    end

    # @private
    def self.worksheet_class    
      @worksheet_class ||= begin
        module_name = self.parent_name
        "#{module_name}::Worksheet".constantize        
      rescue NameError => e
        Worksheet
      end
    end

    # @private
    def excel_class        
      self.class.excel_class
    end

    # @private
    def worksheet_class        
      self.class.worksheet_class
    end

    include MethodHelpers

  private

    def method_missing(name, *args) 
      super unless name.to_s[0,1] =~ /[A-Z]/
      raise ObjectNotAlive, 'method missing: workbook not alive' unless alive?
      if ::ERRORMESSAGE_JRUBY_BUG 
        begin
          @ole_workbook.send(name, *args)
        rescue Java::OrgRacobCom::ComFailException 
          raise VBAMethodMissingError, "unknown VBA property or method #{name.inspect}"
        end
      else
        begin
          @ole_workbook.send(name, *args)
        rescue NoMethodError 
          raise VBAMethodMissingError, "unknown VBA property or method #{name.inspect}"
        end
      end
    end

  end

public

  # @private
  class WorkbookBlocked < WorkbookREOError         
  end

  # @private
  class WorkbookNotSaved < WorkbookREOError        
  end

  # @private
  class WorkbookLinked < WorkbookREOError        
  end

  # @private
  class WorkbookReadOnly < WorkbookREOError        
  end

  # @private
  class WorkbookBeingUsed < WorkbookREOError       
  end

  # @private
  class WorkbookConnectingUnsavedError < WorkbookREOError        
  end

  # @private
  class WorkbookConnectingBlockingError < WorkbookREOError       
  end

  # @private
  class WorkbookConnectingUnknownError < WorkbookREOError       
  end

  # @private
  class FileAlreadyExists < FileREOError           
  end

  # @private
  class FileNameNotGiven < FileREOError            
  end

  # @private
  class FileNotFound < FileREOError                
  end
  
  
  Book = Workbook

end
