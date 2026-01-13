// Stats Counter Animation
(function () {
  "use strict";

  // Format number to Juta or M (no Ribu, use decimal Juta instead)
  function formatNumber(num) {
    if (num >= 1000000000) {
      var billions = (num / 1000000000).toFixed(1);
      return billions.replace(".0", "") + " M";
    } else if (num >= 1000) {
      // Always show as Juta, even for thousands (e.g., 0.1 Juta, 0.5 Juta)
      var millions = (num / 1000000).toFixed(1);
      return millions.replace(".0", "") + " Juta";
    }
    return num.toString();
  }

  // Counter animation function
  function animateCounter(element) {
    var target = parseInt(element.getAttribute("data-target"));
    var duration = 2000;
    var frameRate = 30;
    var totalFrames = duration / frameRate;
    var currentFrame = 0;

    var counter = setInterval(function () {
      currentFrame++;
      var progress = currentFrame / totalFrames;
      var currentValue = Math.floor(progress * target);

      element.textContent = formatNumber(currentValue);

      if (currentFrame >= totalFrames) {
        element.textContent = formatNumber(target);

        // Show plus sign when animation completes
        var plusSign = element.parentElement.querySelector(".plus-sign");
        if (plusSign) {
          plusSign.style.opacity = "1";
        }

        clearInterval(counter);
      }
    }, frameRate);
  }

  // Start animation
  var hasAnimated = false;

  function startCounterAnimation() {
    if (hasAnimated) return;

    var statsSection = document.getElementById("stat-section");
    if (!statsSection) return;

    var rect = statsSection.getBoundingClientRect();
    var windowHeight =
      window.innerHeight || document.documentElement.clientHeight;
    var isVisible = rect.top <= windowHeight * 0.8 && rect.bottom >= 0;

    if (isVisible) {
      hasAnimated = true;

      // Add delay to sync with WOW animations
      setTimeout(function () {
        var counters = document.querySelectorAll(".counter");
        for (var i = 0; i < counters.length; i++) {
          animateCounter(counters[i]);
        }
      }, 600);
    }
  }

  // Initialize when document is ready
  function init() {
    // Check on scroll
    window.addEventListener("scroll", startCounterAnimation);

    // Check on load
    window.addEventListener("load", startCounterAnimation);

    // Initial check
    setTimeout(startCounterAnimation, 500);
  }

  // Start initialization
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
