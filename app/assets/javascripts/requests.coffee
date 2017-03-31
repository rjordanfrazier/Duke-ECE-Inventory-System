# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

$(document).on "page:change", ->
	$('.response').hide()
	$('#user_id').attr('disabled', true)
	$('#request_response').attr('required', 'required')
	$('#dd-check').click ->
		if ($('#dd-check').is(':checked')) # direct disbursement
			$('#user_id').prop('disabled', false)
			$('.response').show()
			$('.reason').hide()
			$('#request_response').removeAttr('required')
		else
			$('#user_id').prop('disabled', true)
			$('.response').hide()
			$('.reason').show()
			$('#request_response').attr('required', 'required')
