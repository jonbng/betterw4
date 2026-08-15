jQuery(function ($) {
$(document).ajaxError(function (e, XMLHttpRequest, textStatus, errorThrown) {
        var data = XMLHttpRequest.responseText;
        if (XMLHttpRequest.status == 409) {
            alert('Error from remote server: ' + data);
        } else if (XMLHttpRequest.status == 404) {
            alert('Error 404: page not found');
        } else if (XMLHttpRequest.status == 403) {
            if (data.search('Login Required') >= 0) {
                location.href='/';
            } else {
                alert('Error 403: not authorized');
            }
        } else if (textStatus == "parsererror") {
            alert('Invalid response from the remote server');
        } else if (textStatus == "timeout") {
            alert('Timeout - the remote server is not responding');
        } else {
            alert('Unknown error (' + XMLHttpRequest.status + ') while fetching data from remote server');
        }
    });
});