$(document).ready(function() {
  // delete feeds
  $('.delete').click(function(){
    var feed_id = $(this).closest('tr').attr('id');
    $.ajax({
      url: '/feed/' + feed_id,
      type: 'DELETE',
      success: fade(feed_id)
    });
  });

  $('.show_advanced').click(function(){
    $('.show_advanced').hide();
    $('.advanced').show();
  })

  // show delete link on hover
  $('tr').hover(
    function(){ $(this).find('.delete').show(); },
    function(){ $(this).find('.delete').hide(); }
  );

  var fade = function(feed_id) {
    $('tbody').append(
      $('#'+feed_id).addClass('faded')
        .find('.delete').remove().end()
    );
    alert('An email has been sent to '+
      $('#'+feed_id+' .email').text()+
      ' to confirm deletion.');
  };
});
