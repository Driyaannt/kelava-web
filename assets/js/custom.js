var scrollLink = $(".page-scroll");
var navLink = $('a.page-scroll[href*="#"]:not([href="#"])');
var contentSelector = document.getElementById("kelava-content");

function initScrollLink() {
  scrollLink = $(".page-scroll");
  $('a.page-scroll[href*="#"]:not([href="#"])').on("click", function () {
    if (
      location.pathname.replace(/^\//, "") ==
        this.pathname.replace(/^\//, "") &&
      location.hostname == this.hostname
    ) {
      var target = $(this.hash);
      target = target.length ? target : $("[name=" + this.hash.slice(1) + "]");
      var url = new URL(this.href);
      var c = url.searchParams.get("c");
      var currentC = contentSelector.dataset.page;
      if (c !== currentC) {
        loadContent(c + ".html");
        $("html, body").animate(
          {
            scrollTop: 0,
          },
          600,
          "easeInOutExpo"
        );
      } else if (target.length) {
        $("html, body").animate(
          {
            scrollTop: target.offset().top - 60,
          },
          1200,
          "easeInOutExpo"
        );
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
      xhttp.onreadystatechange = function () {
        if (this.readyState == 4) {
          if (this.status == 200) {
            elmnt.innerHTML = this.responseText;
            initScrollLink();
          }
          if (this.status == 404) {
            elmnt.innerHTML = "Page not found.";
          }
          /* Remove the attribute, and call this function once more: */
          elmnt.removeAttribute("kelava-include-html");
          includeHTML();
        }
      };
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
    xhttp.onreadystatechange = function () {
      if (this.readyState == 4) {
        if (this.status == 200) {
          contentSelector.innerHTML = this.responseText;
          contentSelector.dataset.page = file.replace(".html", "");
          includeHTML();
        }
        if (this.status == 404) {
          contentSelector.innerHTML = "Page not found.";
        }
      }
    };
    xhttp.open("GET", file, true);
    xhttp.send();
    /* Exit the function: */
    return;
  }
}

$(function () {
  var url = new URL(location.href);
  var c = url.searchParams.get("c") || "home";
  var currentC = contentSelector.dataset.page;
  if (c !== currentC) {
    loadContent(c + ".html");
  }
  includeHTML();
});

// TESTIMONIAL CARD ROTATION ANIMATION
(function initTestimonialRotation() {
  var positions = [
    {
      x: 0,
      y: 0,
      opacity: 0.75,
      z: 0,
      shadow: "0 4px 9px rgba(241,241,244,0.8)",
    },
    {
      x: 79,
      y: 125,
      opacity: 1,
      z: 1,
      shadow: "-5px 8px 8px 0 rgba(82,89,129,0.05)",
    },
    {
      x: 0,
      y: 250,
      opacity: 0.75,
      z: 0,
      shadow: "0 4px 9px rgba(241,241,244,0.8)",
    },
    { x: 0, y: 400, opacity: 0, z: -1, shadow: "none" },
  ];

  var currentIndex = 0;
  var cards;
  var rotationInterval;
  var isInitialized = false; // Flag to prevent double initialization

  function findAndInitCards() {
    // Prevent double initialization
    if (isInitialized) {
      console.log("⚠️ CARD ROTATION: Already initialized, skipping");
      return;
    }

    cards = document.querySelectorAll("#card-slider .testimonial-card");

    if (!cards || cards.length === 0) {
      setTimeout(findAndInitCards, 300);
      return;
    }

    isInitialized = true; // Mark as initialized
    console.log("✅ CARD ROTATION: Found " + cards.length + " cards");

    // Apply initial positions
    for (var i = 0; i < cards.length; i++) {
      applyPosition(cards[i], positions[i]);
    }

    // Start rotation after 2 seconds
    setTimeout(function () {
      console.log("🎬 CARD ROTATION: Starting animation (every 5 seconds)");
      rotationInterval = setInterval(rotateCards, 5000);
    }, 2000);
  }

  function applyPosition(card, pos) {
    card.style.transform = "translate(" + pos.x + "px, " + pos.y + "px)";
    card.style.opacity = pos.opacity;
    card.style.zIndex = pos.z;
    card.style.boxShadow = pos.shadow;
  }

  function rotateCards() {
    if (!cards || cards.length === 0) return;

    currentIndex = (currentIndex + 1) % cards.length;
    console.log("🔄 CARD ROTATION: Moving to position " + currentIndex);

    for (var i = 0; i < cards.length; i++) {
      var relativePos = (i - currentIndex + cards.length) % cards.length;
      applyPosition(cards[i], positions[relativePos]);
    }
  }

  // Try to init on page load
  $(document).ready(function () {
    setTimeout(findAndInitCards, 500);
  });

  // Also try on window load
  $(window).on("load", function () {
    setTimeout(findAndInitCards, 1000);
  });
})();
