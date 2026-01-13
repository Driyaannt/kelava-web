// Video Modal Script
(function () {
  "use strict";

  // Wait for everything to load
  function initVideoModal() {
    var modal = document.getElementById("videoModal");
    var btn = document.getElementById("playVideoBtn");
    var closeBtn = document.getElementById("closeModal");
    var video = document.getElementById("introVideo");

    console.log("Video Modal Init - Elements found:", {
      modal: !!modal,
      btn: !!btn,
      closeBtn: !!closeBtn,
      video: !!video,
    });

    if (!modal || !btn || !closeBtn || !video) {
      console.error("Video modal elements not found!");
      console.log(
        "Available buttons with id:",
        document.querySelectorAll('[id*="play"]')
      );
      return;
    }

    // Open modal with smooth animation
    btn.addEventListener(
      "click",
      function (e) {
        e.preventDefault();
        e.stopPropagation();
        console.log("Opening video modal...");

        // Show modal first
        modal.style.display = "block";

        // Force reflow to ensure display change is applied
        modal.offsetHeight;

        // Then add animation class
        modal.classList.add("show");

        // Start video after animation starts
        setTimeout(function () {
          video.currentTime = 0;
          video.play().catch(function (err) {
            console.log("Video autoplay blocked:", err);
          });
        }, 300);
      },
      false
    );

    // Close modal function with animation
    function closeModal() {
      console.log("Closing modal");
      modal.classList.remove("show");
      modal.classList.add("hide");

      video.pause();
      video.currentTime = 0;

      // Hide after animation completes
      setTimeout(function () {
        modal.style.display = "none";
        modal.classList.remove("hide");
      }, 300);
    }

    // Close button
    closeBtn.addEventListener(
      "click",
      function (e) {
        e.preventDefault();
        closeModal();
      },
      false
    );

    // Click outside video to close
    modal.addEventListener(
      "click",
      function (e) {
        if (e.target === modal) {
          closeModal();
        }
      },
      false
    );

    // ESC key to close
    document.addEventListener(
      "keydown",
      function (e) {
        if (e.key === "Escape" && modal.style.display === "block") {
          closeModal();
        }
      },
      false
    );

    console.log("Video modal initialized successfully!");
  }

  // Initialize when everything is ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initVideoModal);
  } else {
    // DOM already loaded
    initVideoModal();
  }

  // Also try on window load as backup
  window.addEventListener("load", function () {
    setTimeout(initVideoModal, 500);
  });
})();
