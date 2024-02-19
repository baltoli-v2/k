// Copyright (c) Runtime Verification, Inc. All Rights Reserved.
package org.kframework.utils.inject;

import static org.kframework.utils.errorsystem.KException.ExceptionType.*;

import com.google.inject.AbstractModule;
import com.google.inject.Provides;
import java.io.File;
import org.apache.commons.io.FilenameUtils;
import org.kframework.main.GlobalOptions;
import org.kframework.utils.errorsystem.KEMException;
import org.kframework.utils.errorsystem.KExceptionManager;
import org.kframework.utils.file.DefinitionDir;
import org.kframework.utils.file.FileUtil;
import org.kframework.utils.file.KompiledDir;
import org.kframework.utils.file.WorkingDir;
import org.kframework.utils.options.OuterParsingOptions;
import org.kframework.utils.options.OutputDirectoryOptions;

/**
 * Provides the information needed for tools that parse definitions from source to have access to
 * {@link FileUtil}.
 *
 * <p>Used currently by kompile, and kdep.
 */
public class OuterParsingModule extends AbstractModule {

  @Override
  protected void configure() {
    binder().requireAtInjectOnConstructors();
  }

  @Provides
  @DefinitionDir
  File definitionDir(@KompiledDir File kDir) {
    return kDir.getParentFile();
  }

  @Provides
  @KompiledDir
  File kompiledDir(
      OuterParsingOptions options, @WorkingDir File workingDir, OutputDirectoryOptions output) {
    if (output.outputDirectory != null) {
      if (output.directory != null)
        throw KEMException.criticalError(
            "Cannot use both --directory and --output-definition at the same time.");
      File f = new File(output.outputDirectory);
      if (f.isAbsolute()) return f;
      return new File(workingDir, output.outputDirectory);
    } else if (output.directory != null) {
      KExceptionManager kem = new KExceptionManager(new GlobalOptions());
      kem.registerCompilerWarning(
          DEPRECATED_DIRECTORY_FLAG,
          "The --directory option is deprecated. Please use --output-definition instead.");
      kem.print();
      File f = new File(output.directory);
      if (!f.isAbsolute()) f = new File(workingDir, output.directory).getAbsoluteFile();

      return new File(
          f,
          FilenameUtils.removeExtension(
                  options
                      .mainDefinitionFile(new FileUtil(null, workingDir, null, null, null))
                      .getName())
              + "-kompiled");
    }
    // bootstrap the part of FileUtil we need
    return new File(
        workingDir,
        FilenameUtils.removeExtension(
                options
                    .mainDefinitionFile(new FileUtil(null, workingDir, null, null, null))
                    .getName())
            + "-kompiled");
  }
}
