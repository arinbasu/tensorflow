

#' Install TensorFlow and it's dependencies
#'
#' @inheritParams reticulate::conda_list
#'
#' @param method Installation method. By default, "auto" automatically finds a
#'   method that will work in the local environment. Change the default to force
#'   a specific installation method. Note that the "virtualenv" method is not
#'   available on Windows (as this isn't supported by TensorFlow). Note also
#'   that since this command runs without privillege the "system" method is
#'   available only on Windows.
#' @param version TensorFlow version to install (must be either "latest" or a
#'   full major.minor.patch specification, e.g. "1.1.0").
#' @param gpu Install the GPU version of TensorFlow
#' @param package_url URL of the TensorFlow package to install (if not specified
#'   this is determined automatically). Note that if this parameter is provied
#'   then the `version` and `gpu` parameters are ignored.
#'
#' @importFrom jsonlite fromJSON
#'
#' @export
install_tensorflow <- function(method = c("auto", "virtualenv", "conda", "system"),
                               version = "latest",
                               gpu = FALSE,
                               package_url = NULL,
                               conda = "auto") {

  # verify os
  if (!is_windows() && !is_osx() && !is_ubuntu()) {
    stop("Unable to install TensorFlow on this platform. ",
         "Binary installation is available for Windows, Linux, and Ubuntu.")
  }

  # verify 64-bit
  if (.Machine$sizeof.pointer != 8) {
    stop("Unable to install TensorFlow on this platform.",
         "Binary installation is only available for 64-bit platforms.")
  }

  # resolve and validate method
  method <- match.arg(method)
  if (identical(method, "system") && !is_windows()) {
    stop("Installing TensorFlow into the system library is only supported on Windows",
         call. = FALSE)
  }
  if (identical(method, "virtualenv") && is_windows()) {
    stop("Installing TensorFlow into a virtualenv is not supported on Windows",
         call. = FALSE)
  }

  # flags indicating what methods are available
  method_available <- function(name) method %in% c("auto", name)
  virtualenv_available <- method_available("virtualenv")
  conda_available <- method_available("conda")
  system_available <- is_windows() && method_available("site")

  # resolve and look for conda
  conda <- tryCatch(conda_binary(conda), error = function(e) NULL)
  have_conda <- conda_available && !is.null(conda)

  # mac and linux
  if (is_unix()) {

    # check for explicit conda method
    if (identical(method, "conda")) {

      # validate that we have conda
      if (!have_conda)
        stop("Conda installation failed (no conda binary found)\n", call. = FALSE)

      # do install
      install_tensorflow_conda(conda, version, gpu, package_url)

    } else {

      # find system python binary
      python <- python_unix_binary("python")
      if (is.null(python))
        stop("Unable to locate Python on this system.", call. = FALSE)

      # find other required tools
      pip <- python_unix_binary("pip")
      have_pip <- !is.null(pip)
      virtualenv <- python_unix_binary("virtualenv")
      have_virtualenv <- virtualenv_available && !is.null(virtualenv)

      # if we don't have pip and virtualenv then try for conda if it's allowed
      if ((!have_pip || !have_virtualenv) && have_conda) {

        install_tensorflow_conda(conda, version, gpu, package_url)


      # otherwise this is either an "auto" installation w/o working conda
      # or it's an explicit "virtualenv" installation
      } else {

        # validate that we have the required tools for the method
        install_commands <- NULL
        if (is_osx()) {
          if (!have_pip)
            install_commands <- c(install_commands, "$ sudo easy_install pip")
          if (!have_virtualenv)
            install_commands <- c(install_commands, "$ sudo pip install --upgrade virtualenv")
          if (!is.null(install_commands))
            install_commands <- paste(install_commands, collapse = "\n")
        } else {
          if (!have_pip)
            install_commands <- c(install_commands, "python-pip")
          if (!have_virtualenv)
            install_commands <- c(install_commands, "python-virtualenv")
          if (!is.null(install_commands)) {
            install_commands <- paste("$ sudo apt-get install",
                                      paste(install_commands, collapse = " "))
          }

        }
        if (!is.null(install_commands)) {
          stop("Prerequisites for installing TensorFlow not available.\n\n",
               "Execute the following at a terminal to install the prerequisites:\n\n",
               install_commands, "\n\n", call. = FALSE)
        }

        # do the install
        install_tensorflow_virtualenv(python, virtualenv, version, gpu, package_url)

      }
    }

  # windows installation
  } else {

    # determine whether we have system python
    python_versions <- py_versions_windows()
    python_versions <- python_versions[python_versions$type == "PythonCore",]
    python_versions <- python_versions[python_versions$version == "3.5",]
    python_versions <- python_versions[python_versions$arch == "x64",]
    have_system <- nrow(python_versions) > 0
    if (have_system)
      python_system_version <- python_versions[1,]

    # resolve auto
    if (identical(method, "auto")) {

        if (!have_system && !have_conda) {
          stop("Installing TensorFlow requires a 64-bit version of Python 3.5\n\n",
               "Please install 64-bit Python 3.5 to continue, supported versions include:\n\n",
               " - Anaconda Python (Recommended): https://www.continuum.io/downloads#windows\n",
               " - Python Software Foundation   : https://www.python.org/downloads/release/python-353/\n\n",
               "Note that if you install from Python Software Foundation you must install exactly\n",
               "Python 3.5 (as opposed to 3.6 or higher).\n\n",
               call. = FALSE)
        } else if (have_conda) {
          method <- "conda"
        } else if (have_system) {
          method <- "system"
        }
    }

    if (identical(method, "conda")) {

      # validate that we have conda
      if (!have_conda) {
        stop("Conda installation failed (no conda binary found)\n\n",
             "Install Anaconda 3.x for Windows (https://www.continuum.io/downloads#windows)\n",
             "before installing TensorFlow.",
             call. = FALSE)
      }

      # do the install
      install_tensorflow_conda(conda, version, gpu, package_url)

    } else if (identical(method, "system")) {

      # if we don't have it then error
      if (!have_system) {
        stop("Installing TensorFlow requires a 64-bit version of Python 3.5\n\n",
             "Please install 64-bit Python 3.5 from this location to continue:\n\n",
             " - https://www.python.org/downloads/release/python-353/\n\n",
             "Note that you must install exactly Python 3.5 (as opposed to 3.6 or higher).\n\n",
             call. = FALSE)
      }

      # do system installation
      python <- python_system_version$executable_path
      pip <- file.path(python_system_version$install_path, "Scripts", "pip.exe")
      install_tensorflow_windows_system(python, pip, version, gpu, package_url)

    } else {
      stop("Invalid/unexpected installation method '", method, "'",
           call. = FALSE)
    }
  }

  cat("\nInstallation of TensorFlow complete.\n\n")
  invisible(NULL)
}

install_tensorflow_conda <- function(conda, version, gpu, package_url) {

  # create conda environment if we need to
  envname <- "r-tensorflow"
  conda_envs <- conda_list(conda = conda)
  conda_env <- subset(conda_envs, conda_envs$name == envname)
  if (nrow(conda_env) == 1) {
    cat("Using", envname, "conda environment for TensorFlow installation\n")
    python <- conda_env$python
  }
  else {
    cat("Creating", envname, "conda environment for TensorFlow installation...\n")
    packages <- ifelse(is_windows(), "python=3.5", "python")
    python <- conda_create(envname, packages = packages, conda = conda)
  }

  # determine tf version
  if (version == "latest") {
    cat("Determining latest release of TensorFlow...")
    releases <- fromJSON("https://api.github.com/repos/tensorflow/tensorflow/releases")
    latest <- subset(releases, grepl("^v\\d+\\.\\d+\\.\\d+$", releases$tag_name))$tag_name[[1]]
    version <- sub("v", "", latest)
    cat("done\n")
  }

  # determine python version
  py_version <- python_version(python)
  py_version_str <- if (is_osx()) {
    if (py_version >= "3.0")
      "py3-none"
    else
      "py2-none"
  } else {
    if (py_version >= "3.0") {
      ver <- gsub(".", "", as.character(py_version), fixed = TRUE)
      sprintf("cp%s-cp%sm", ver, ver)
    } else {
      "cp27-none"
    }
  }

  # determine arch
  arch <- ifelse(is_windows(), "win_amd64", ifelse(is_osx(), "any", "linux_x86_64"))

  # determine package_url
  if (is.null(package_url)) {
    platform <- ifelse(is_windows(), "windows", ifelse(is_osx(), "mac", "linux"))
    package_url <- sprintf(
      "https://storage.googleapis.com/tensorflow/%s/%s/tensorflow-%s-%s-%s.whl",
      platform,
      ifelse(gpu, "gpu", "cpu"),
      version,
      py_version_str,
      arch
    )
  }

  # install base tensorflow using pip
  cat("Installing TensorFlow...\n")
  conda_install(envname, package_url, pip = TRUE, conda = conda)

  # install additional packages
  conda_install(envname, tf_extra_pkgs(), conda = conda)

}

install_tensorflow_virtualenv <- function(python, virtualenv, version, gpu, package_url) {

  # determine python version to use
  is_python3 <- python_version(python) >= "3.0"
  pip_version <- ifelse(is_python3, "pip3", "pip")

  # create virtualenv
  virtualenv_root <- "~/.virtualenvs"
  if (!file.exists(virtualenv_root))
    dir.create(virtualenv_root)

  # remove existing if necessary
  virtualenv_path <- file.path(virtualenv_root, "r-tensorflow")
  if (file.exists(virtualenv_path))
    unlink(virtualenv_path, recursive = TRUE)

  cat("Creating virtualenv for TensorFlow at ", virtualenv_path, "\n")
  result <- system2(virtualenv, shQuote(c(
    "--system-site-packages",
    "--python", python,
    path.expand(virtualenv_path)))
  )
  if (result != 0L)
    stop("Error ", result, " occurred creating virtualenv at ", virtualenv_path,
         call. = FALSE)

  # install tensorflow and related dependencies
  virtualenv_bin <- function(bin) path.expand(file.path(virtualenv_path, "bin", bin))
  pkgs <- tf_pkgs(version, gpu, package_url)
  cmd <- sprintf("%ssource %s && %s install --ignore-installed --upgrade %s%s",
                 ifelse(is_osx(), "", "/bin/bash -c \""),
                 shQuote(path.expand(virtualenv_bin("activate"))),
                 shQuote(path.expand(virtualenv_bin(pip_version))),
                 paste(shQuote(pkgs), collapse = " "),
                 ifelse(is_osx(), "", "\""))
  cat("Installing TensorFlow...\n")
  result <- system(cmd)
  if (result != 0L)
    stop("Error ", result, " occurred installing TensorFlow", call. = FALSE)
}


install_tensorflow_windows_system <- function(python, pip, version, gpu, package_url) {

  # ensure pip is up to date
  cat("Preparing for installation (updating pip if necessary)\n")
  result <- system2(python, c("-m", "pip", "install", "--upgrade", "pip"))
  if (result != 0L)
    stop("Error ", result, " occurred updating pip", call. = FALSE)

  # install tensorflow and dependencies (don't install scipy b/c it requires
  # native code compilation)
  cat("Installing TensorFlow...\n")
  pkgs <- tf_pkgs(version, gpu, package_url, scipy = FALSE)
  result <- system2(pip, c("install", "--upgrade --ignore-installed",
                           paste(shQuote(pkgs), collapse = " ")))
  if (result != 0L)
    stop("Error ", result, " occurred installing tensorflow package", call. = FALSE)

  cat("\nInstallation of TensorFlow complete.\n\n")
}


python_unix_binary <- function(bin) {
  locations <- file.path(c("/usr/local/bin", "/usr/bin"), bin)
  locations <- locations[file.exists(locations)]
  if (length(locations) > 0)
    locations[[1]]
  else
    NULL
}

python_version <- function(python) {

  # check for the version
  result <- system2(python, "--version", stdout = TRUE, stderr = TRUE)

  # check for error
  error_status <- attr(result, "status")
  if (!is.null(error_status))
    stop("Error ", error_status, " occurred while checking for python version", call. = FALSE)

  # parse out the major and minor version numbers
  matches <- regexec("^[^ ]+\\s+(\\d+)\\.(\\d+).*$", result)
  matches <- regmatches(result, matches)[[1]]
  if (length(matches) != 3)
    stop("Unable to parse Python version '", result[[1]], "'", call. = FALSE)

  # return as R numeric version
  numeric_version(paste(matches[[2]], matches[[3]], sep = "."))
}


# form list of tf pkgs
tf_pkgs <- function(version, gpu, package_url, scipy = TRUE) {
  package <- package_url
  if (is.null(package))
    package <- sprintf("tensorflow%s%s",
                       ifelse(gpu, "-gpu", ""),
                       ifelse(version == "latest", "", paste0("==", version)))
  c(package, tf_extra_pkgs(scipy = scipy))
}

# additional dependencies to install (required by some features of keras)
tf_extra_pkgs <- function(scipy = TRUE) {
  pkgs <- c("h5py", "pyyaml",  "requests",  "Pillow")
  if (scipy)
    c(pkgs, "scipy")
  else
    pkgs
}


