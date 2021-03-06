# Rails 3 Client Side Validations - v<%= ClientSideValidations::Backbone::VERSION %>
# https://github.com/dockyard/client_side_validations-backbone
#
# Copyright (c) <%= DateTime.now.year %> Brian Cardarella
# Licensed under the MIT license
# http://www.opensource.org/licenses/mit-license.php

$ = jQuery
$.fn.validate = ->
  @filter('form[data-validate]').each ->
    form = $(@)
    settings = window.ClientSideValidations.forms[form.attr('id')]
    addError = (element, message) ->
      ClientSideValidations.formBuilders[settings.type].add(element, settings, message)
    removeError = (element) ->
      ClientSideValidations.formBuilders[settings.type].remove(element, settings)

    # Set up the events for the form
    form.submit -> form.isValid(settings.validators)
    form.bind(event, binding) for event, binding of {
      'ajax:beforeSend'     : (eventData) -> form.isValid(settings.validators) if eventData.target == @
      'form:validate:after' : (eventData) -> ClientSideValidations.callbacks.form.after( form, eventData)
      'form:validate:before': (eventData) -> ClientSideValidations.callbacks.form.before(form, eventData)
      'form:validate:fail'  : (eventData) -> ClientSideValidations.callbacks.form.fail(  form, eventData)
      'form:validate:pass'  : (eventData) -> ClientSideValidations.callbacks.form.pass(  form, eventData)
    }
    form.find('[data-validate="true"]:input:enabled:not(:radio)').live(event, binding) for event, binding of {
      'focusout':                -> $(@).isValid(settings.validators)
      'change':                  -> $(@).data('changed', true)
      # Callbacks
      'element:validate:after':  (eventData) -> ClientSideValidations.callbacks.element.after($(@), eventData)
      'element:validate:before': (eventData) -> ClientSideValidations.callbacks.element.before($(@), eventData)
      'element:validate:fail':   (eventData, message) ->
        element = $(@)
        ClientSideValidations.callbacks.element.fail(element, message, ->
          addError(element, message)
        , eventData)
      'element:validate:pass':   (eventData) ->
        element = $(@)
        ClientSideValidations.callbacks.element.pass(element, ->
          removeError(element)
        , eventData)
    }

    # Checkboxes - Live events don't support filter
    form.find('[data-validate="true"]:checkbox').live('click', -> $(@).isValid(settings.validators))

    # Inputs for confirmations
    form.find('[id*=_confirmation]').each ->
      confirmationElement = $(@)
      element = form.find("##{@id.match(/(.+)_confirmation/)[1]}[data-validate='true']:input")
      if element[0]
        $("##{confirmationElement.attr('id')}").live(event, binding) for event, binding of {
          'focusout': -> element.data('changed', true).isValid(settings.validators)
          'keyup'   : -> element.data('changed', true).isValid(settings.validators)
        }

$.fn.isValid = (validators) ->
  obj = $(@[0])
  if obj.is('form')
    validateForm(obj, validators)
  else
    validateElement(obj, validators[@[0].name])

validateForm = (form, validators) ->
  form.trigger('form:validate:before')

  valid = true
  form.find('[data-validate="true"]:input:enabled').each ->
    valid = false if $(@).isValid(validators)

  if valid then form.trigger('form:validate:pass') else form.trigger('form:validate:fail')

  form.trigger('form:validate:after')
  valid

validateElement = (element, validators) ->
  element.trigger('element:validate:before')

  if element.data('changed') != false
    valid = true
    element.data('changed', false)

    # Because 'length' is defined on the list of validators we cannot call jQuery.each on
    context = ClientSideValidations.validators.local
    for kind, fn of context
      if validators[kind] and (message = fn.call(context, element, validators[kind]))
        element.trigger('element:validate:fail', message).data('valid', false)
        valid = false
        break

    if valid
      context = ClientSideValidations.validators.remote
      for kind, fn of context
        if validators[kind] and (message = fn.call(context, element, validators[kind]))
          element.trigger('element:validate:fail', message).data('valid', false)
          valid = false
          break

    if valid
      element.data('valid', null)
      element.trigger('element:validate:pass')

  element.trigger('element:validate:after')
  element.data('valid') == false ? false : true

# Main hook
# If new forms are dynamically introduced into the DOM the .validate() method
# must be invoked on that form
$(-> $('form[data-validate]').validate())

window.ClientSideValidations =
  forms: {}
  models: {}
  validators:
    all: -> jQuery.extend({}, ClientSideValidations.validators.local, ClientSideValidations.validators.remote)
    local:
      presence: (element, options) ->
        options.message if /^\s*$/.test(element.val() || '')

      acceptance: (element, options) ->
        switch element.attr('type')
          when 'checkbox'
            unless element.attr('checked')
              return options.message
          when 'text'
            if element.val() != (options.accept?.toString() || '1')
              return options.message

      format: (element, options) ->
        message = @presence(element, options)
        if message
          return if options.allow_blank == true
          return message
        
        return options.message if options.with and !options.with.test(element.val())
        return options.message if options.without and options.without.test(element.val())

      numericality: (element, options) ->
        unless /^-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d*)?$/.test(element.val())
          return options.messages.numericality

        if options.only_integer and !/^[+-]?\d+$/.test(element.val())
          return options.messages.only_integer

        CHECKS =
          greater_than: '>'
          greater_than_or_equal_to: '>='
          equal_to: '=='
          less_than: '<'
          less_than_or_equal_to: '<='

        # options[check] may be 0 so we must check for undefined
        for check, operator of CHECKS when options[check]?
          fn = new Function("return #{element.val()} #{operator} #{options[check]}")
          return options.messages[check] unless fn()

        if options.odd and !(parseInt(element.val(), 10) % 2)
          return options.messages.odd

        if options.even and (parseInt(element.val(), 10) % 2)
          return options.messages.even

      length: (element, options) ->
        tokenizer = options.js_tokenizer || "split('')"
        tokenized_length = new Function('element', "return (element.val().#{tokenizer} || '').length")(element)
        CHECKS =
          is: '=='
          minimum: '>='
          maximum: '<='
        blankOptions = {}
        blankOptions.message = if options.is
          options.messages.is
        else if options.minimum
          options.messages.minimum

        message = @presence(element, blankOptions)
        if message
          return if options.allow_blank == true
          return message

        for check, operator of CHECKS when options[check]
          fn = new Function("return #{tokenized_length} #{operator} #{options[check]}")
          return options.messages[check] unless fn()

      exclusion: (element, options) ->
        message = @presence(element, options)
        if message
          return if options.allow_blank == true
          return message

        if options.in
          return options.message if element.val() in (o.toString() for o in options.in)

        if options.range
          lower = options.range[0]
          upper = options.range[1]
          return options.message if element.val() >= lower and element.val() <= upper

      inclusion: (element, options) ->
        message = @presence(element, options)
        if message
          return if options.allow_blank == true
          return message

        if options.in
          return if element.val() in (o.toString() for o in options.in)
          return options.message

        if options.range
          lower = options.range[0]
          upper = options.range[1]
          return if element.val() >= lower and element.val() <= upper
          return options.message

      confirmation: (element, options) ->
        if element.val() != jQuery("##{element.attr('id')}_confirmation").val()
          return options.message

    remote:
      uniqueness: (element, options) ->
        message = ClientSideValidations.validators.local.presence(element, options)
        if message
          return if options.allow_blank == true
          return message

        data = {}
        data.case_sensitive = !!options.case_sensitive
        data.id = options.id if options.id

        if options.scope
          data.scope = {}
          for key, scope_value of options.scope
            scoped_name = element.attr('name').replace(/\[\w+\]$/, "[#{key}]")
            scoped_element = jQuery("[name='#{scoped_name}']")
            if scoped_element[0] and scoped_element.val() != scope_value
              data.scope[key] = scoped_element.val()
              scoped_element.unbind("change.#{element.id}").bind "change.#{element.id}", ->
                element.trigger('change')
                element.trigger('focusout')
            else
              data.scope[key] = scope_value

        # Kind of a hack but this will isolate the resource name and attribute.
        # e.g. user[records_attributes][0][title] => records[title]
        # e.g. user[record_attributes][title] => record[title]
        # Server side handles classifying the resource properly
        if /_attributes\]/.test(element.attr('name'))
          name = element.attr('name').match(/\[\w+_attributes\]/g).pop().match(/\[(\w+)_attributes\]/).pop()
          name += /(\[\w+\])$/.exec(element.attr('name'))[1]
        else
          name = element.attr('name')

        # Override the name if a nested module class is passed
        name = options['class'] + '[' + name.split('[')[1] if options['class']
        data[name] = element.val()

        if jQuery.ajax({
          url: '/validators/uniqueness',
          data: data,
          async: false
        }).status == 200
          return options.message

  formBuilders:
    'ActionView::Helpers::FormBuilder':
      add: (element, settings, message) ->
        if element.data('valid') != false and not jQuery("label.message[for='#{element.attr('id')}']")[0]?
          inputErrorField = jQuery(settings.input_tag)
          labelErrorField = jQuery(settings.label_tag)
          label = jQuery("label[for='#{element.attr('id')}']:not(.message)")

          element.attr('autofocus', false) if element.attr('autofocus')

          element.before(inputErrorField)
          inputErrorField.find('span#input_tag').replaceWith(element)
          inputErrorField.find('label.message').attr('for', element.attr('id'))
          labelErrorField.find('label.message').attr('for', element.attr('id'))
          label.replaceWith(labelErrorField)
          labelErrorField.find('label#label_tag').replaceWith(label)

        jQuery("label.message[for='#{element.attr('id')}']").text(message)

      remove: (element, settings) ->
        errorFieldClass = jQuery(settings.input_tag).attr('class')
        inputErrorField = element.closest(".#{errorFieldClass}")
        label = jQuery("label[for='#{element.attr('id')}']:not(.message)")
        labelErrorField = label.closest(".#{errorFieldClass}")

        if inputErrorField[0]
          inputErrorField.find("##{element.attr('id')}").detach()
          inputErrorField.replaceWith(element)
          label.detach()
          labelErrorField.replaceWith(label)
  
  # Decorates a Backbone Model or child class.  Runs any pre-existing validations first, and if
  # they pass, then it runs the ClientSideValidations.
  decorateModel: (TargetModel, modelName) ->
    TargetModel.prototype._csvModelName = modelName
    originalValidate = TargetModel.prototype.validate
    TargetModel.prototype.validate = (attrs) ->

      # TBD: call CSV form validator events?
      # form.trigger('form:validate:before')
      if originalValidate
        errors = originalValidate.call(@, attrs)
        return errors if errors

      settings = ClientSideValidations.models[modelName]
      validators = settings.validators
      errors = {}
      valid = true

      # TBD: call CSV form validator events?
      # element.trigger('element:validate:before')
      for attr, value of attrs
        ## validateElement is passed the validators for each attr (validators[attr])
        attribute_validators = validators[attr]
        for context in [ClientSideValidations.validators.local, ClientSideValidations.validators.remote]
          unless errors.length
            for kind, fn of context
              if attribute_validators?[kind]
                # Impersonate an element
                element =
                  attr: (a) -> { name: attr }[a]
                  val: -> value
                message = fn.call(context, element, attribute_validators[kind])
                if message
                  # TBD: call CSV form validator events?
                  # element.trigger('element:validate:fail', message).data('valid', false)
                  valid = false
                  errors[attr] = message
                # else
                  # TBD: call CSV form validator events?
                  # element.trigger('element:validate:pass')
                # TBD: call CSV form validator events?
                # element.trigger('element:validate:after')

      # TBD: call CSV form validator events?
      # if errors.length == 0 then form.trigger('form:validate:pass') else form.trigger('form:validate:fail')
      # form.trigger('form:validate:after')
      return errors unless valid
    
  # Decorates a Backbone View or child class
  decorateView: (TargetView) ->
    # Set up our events while preserving other events
    events = {
      'submit'                            : '_csvUpdateAllInputsAndSubmit'
      'focusout input:enabled:not(:radio)': '_csvUpdateInput'
      'change input:enabled:not(:radio)'  : '_csvUpdateInput'
      'click :checkbox'                   : '_csvUpdateCheckbox'
      # Confirmation missing
    }
    events[key] = value for key, value of TargetView.prototype.events
    TargetView.prototype.events = events
    
    originalInitialize = TargetView.prototype.initialize
    TargetView.prototype.initialize = ->
      originalInitialize.apply(@, arguments) if originalInitialize
      
      # Tracks the elements that should show an error - if you haven't changed it,
      # it won't show an error (how obnoxious!)
      @changed = {}
      
      @model?.bind('change', (model) ->
        jQuery(@el).find('input:enabled').each (index, element) =>
          @_csvRemoveError(jQuery(element))
      , @)
      @model?.bind('error', (model, errors) -> 
        for key, message of errors when @changed[key]
          @_csvAddError(jQuery(@el).find("[name='#{keyToAttrName(key, @model._csvModelName)}']"), message)
      , @)
      console?.log "model must be provided for ClientSideValidation Backbone Views" unless @model
    
    #
    # Event handlers
    #
    TargetView.prototype._csvUpdateInput = (event) ->
      attr_name = attrNameToKey(event.target)
      @changed[attr_name] = true if event.type == 'focusout'
      
      update = {}
      update[key] = value for key, value of @model.attributes
      update[attr_name] = jQuery(event.target).val()
      
      @model.set(update)
    
    TargetView.prototype._csvUpdateCheckbox = (event) ->
      console?.log "CHECKBOX COMING SOON"
      
    TargetView.prototype._csvUpdateAllInputsAndSubmit = (event) ->
      update = {}
      update[key] = value for key, value of @model?.attributes

      jQuery(@el).find('input:enabled').each (index, input) =>
        attr_name = attrNameToKey(input)
        @changed[attr_name] = true
        update[attr_name] = jQuery(input).val()

      # Set and sync to server (submit)
      @model.save(update, { success: => @trigger('success') })
      false
    
    #
    #  Helper methods and functions
    #
    TargetView.prototype._csvAddError = (element, message) ->
      settings = window.ClientSideValidations.models[@model._csvModelName]
      ClientSideValidations.formBuilders[settings.type].add(element, settings, message)
    TargetView.prototype._csvRemoveError = (element) ->
      settings = window.ClientSideValidations.models[@model._csvModelName]
      ClientSideValidations.formBuilders[settings.type].remove(element, settings)
    
    attrNameToKey = (element) ->
      jQuery(element).attr('name')?.match(/\[([^\]]+)\]/)?[1]

    keyToAttrName = (attr_name, scope = "") ->
      if scope.length
        "#{scope}[#{attr_name}]"
      else
        "#{attr_name}"
  

  callbacks:
    element:
      after:  (element, eventData)                    ->
      before: (element, eventData)                    ->
      fail:   (element, message, addError, eventData) -> addError()
      pass:   (element, removeError, eventData)       -> removeError()

    form:
      after:  (form, eventData) ->
      before: (form, eventData) ->
      fail:   (form, eventData) ->
      pass:   (form, eventData) ->
