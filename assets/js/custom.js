
var scrollLink = $(".page-scroll");
var navLink = $('a.page-scroll[href*="#"]:not([href="#"])');
var contentSelector = document.getElementById("kelava-content");

function initScrollLink() {
    scrollLink = $(".page-scroll");
        $('a.page-scroll[href*="#"]:not([href="#"])').on('click', function () {
        if (location.pathname.replace(/^\//, '') == this.pathname.replace(/^\//, '') && location.hostname == this.hostname) {
            var target = $(this.hash);
            target = target.length ? target : $('[name=' + this.hash.slice(1) + ']');
            var url = new URL(this.href);
            var c = url.searchParams.get("c");
            var currentC = contentSelector.dataset.page;
            if (c !== currentC) {
                loadContent(c + ".html");
                $('html, body').animate({
                    scrollTop: 0
                }, 600, "easeInOutExpo");
            } else if (target.length) {
                $('html, body').animate({
                    scrollTop: (target.offset().top -60)
                }, 1200, "easeInOutExpo");
            }
            return false;
        }
    });

    $(window).scroll(function () {
        var scrollbarLocation = $(this).scrollTop();
    
        scrollLink.each(function () {
          var off = $(this.hash).offset();
          if (off !== undefined) {
            var sectionOffset = off.top - 73;
            if (sectionOffset <= scrollbarLocation) {
              $(this).parent().addClass("active");
              $(this).parent().siblings().removeClass("active");
            }
          }
        });
      });
}

async function includeHTML() {
    var z, i, elmnt, file, xhttp;
    /* Loop through a collection of all HTML elements: */
    z = document.getElementsByTagName("*");
    for (i = 0; i < z.length; i++) {
        elmnt = z[i];
        /*search for elements with a certain atrribute:*/
        file = elmnt.getAttribute("kelava-include-html");
        if (file) {
            /* Make an HTTP request using the attribute value as the file name: */
            xhttp = new XMLHttpRequest();
            xhttp.onreadystatechange = function() {
                if (this.readyState == 4) {
                    if (this.status == 200) {
                        elmnt.innerHTML = this.responseText;
                        initScrollLink();
                    }
                    if (this.status == 404) {elmnt.innerHTML = "Page not found.";}
                    /* Remove the attribute, and call this function once more: */
                    elmnt.removeAttribute("kelava-include-html");
                    includeHTML();
                }
            }
            xhttp.open("GET", file, true);
            xhttp.send();
            /* Exit the function: */
            return;
        }
    }
}

function loadContent(file) {
    var file, xhttp;
    if (file) {
        /* Make an HTTP request using the attribute value as the file name: */
        xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState == 4) {
                if (this.status == 200) {
                    contentSelector.innerHTML = this.responseText;
                    contentSelector.dataset.page = file.replace(".html", "");
                    includeHTML();
                }
                if (this.status == 404) {contentSelector.innerHTML = "Page not found.";}
            }
        }
        xhttp.open("GET", file, true);
        xhttp.send();
        /* Exit the function: */
        return;
    }
}

$(function() {
    var url = new URL(location.href);
    var c = url.searchParams.get("c") || "home";
    var currentC = contentSelector.dataset.page;
    if (c !== currentC) {
        loadContent(c + ".html");
    }
    includeHTML();
});